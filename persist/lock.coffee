Async = require 'async'
Fs = require 'fs'
Imm = require 'immutable'
Moment = require 'moment'
Path = require 'path'

Atomic = require './atomic'

{CustomError, IOError, TimestampFormat} = require './utils'

leaseTime = 3 * 60 * 1000 # ms
leaseRenewalInterval = 1 * 60 * 1000 # ms

class Lock
	constructor: (@_path, @_tmpDirPath, @_nextExpiryTimestamp, code) ->
		if code isnt 'privateaccess'
			# See Lock.acquire instead
			throw new Error "Lock constructor should only be used internally"

		@_released = false
		@_isCheckingForLock = false

		@_renewInterval = setInterval =>
			@_renew (err) =>
				if err
					console.error err
					console.error err.stack
					return
		, leaseRenewalInterval

	@acquire: (dataDir, lockId, cb, isCheckingForLock = false) ->
		tmpDirPath = Path.join(dataDir, '_tmp')
		lockDirDest = Path.join(dataDir, '_locks', lockId)

		lockDir = null
		lockDirOp = null
		expiryTimestamp = null

		Async.series [
			(cb) ->
				Atomic.writeDirectory lockDirDest, tmpDirPath, (err, tmpLockDir, op) ->
					if err
						cb new IOError err
						return

					lockDir = tmpLockDir
					lockDirOp = op
					cb()
			(cb) ->
				Lock._writeMetadata lockDir, tmpDirPath, (err) ->
					if err
						cb new IOError err
						return
					cb()
			(cb) ->
				Lock._writeExpiryTimestamp lockDir, tmpDirPath, (err, ts) ->
					if err
						cb err
						return

					expiryTimestamp = ts
					cb()
			(cb) ->
				lockDirOp.commit (err) ->
					if err
						# If lock is already taken
						if err.code in ['EPERM', 'ENOTEMPTY']
							Lock._cleanIfStale dataDir, lockId, cb
							unless isCheckingForLock
								Lock._acquireWhenFree dataDir, lockId
							return

						cb new IOError err
						return

					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new Lock(lockDirDest, tmpDirPath, expiryTimestamp, 'privateaccess')

	@_acquireWhenFree: (dataDir, lockId) ->
		console.log "Starting checkLockInterval..."

		checkLockInterval = setInterval(=>
			# Calls @acquire() with a truthy argument for isCheckingForLock
			# TODO: Self-contained & compact version of @acquire()
			@acquire(dataDir, lockId, (err, result) ->
				if err
					console.log "Still locked... :("
					return

				console.log "Lock has disappeared, acquired you a lock!"
				clearInterval(checkLockInterval)
				global.ActiveSession.persist.eventBus.trigger 'clientFile:lockAcquired', result
			, true)
		, 1000)

	@_cleanIfStale: (dataDir, lockId, cb) ->
		tmpDirPath = Path.join(dataDir, '_tmp')
		lockDir = Path.join(dataDir, '_locks', lockId)

		expiryLock = null

		Async.series [
			(cb) ->
				Lock._isStale lockDir, (err, isStale, metadata) ->
					if err
						cb err
						return

					if isStale
						# Proceed
						cb()
					else
						cb new LockInUseError(metadata)
			(cb) ->
				# The lock has expired, so we need to safely reclaim it while
				# preventing others from doing the same.

				Lock.acquire dataDir, lockId + '.expiry', (err, result) ->
					if err
						cb err
						return

					expiryLock = result
					cb()
			(cb) ->
				Lock._isStale lockDir, (err, isStale, metadata) ->
					if err
						cb err
						return

					if isStale
						# Proceed
						cb()
					else
						cb new LockInUseError(metadata)
			(cb) ->
				Atomic.deleteDirectory lockDir, tmpDirPath, (err) ->
					if err
						cb new IOError err
						return

					cb()
			(cb) ->
				expiryLock.release cb
		], (err) ->
			if err
				cb err
				return

			Lock.acquire dataDir, lockId, cb

	@_isStale: (lockDir, cb) ->
		Lock._readExpiryTimestamp lockDir, (err, ts, metadata) ->
			if err
				cb err
				return

			if ts?
				now = Moment()
				isStale = Moment(ts, TimestampFormat).isBefore now

				cb null, isStale, metadata
				return

			# OK, there weren't any expiry timestamps in the directory.
			# That should be impossible, and also kinda sucks.
			console.error "Detected lock dir with no expiry timestamp: #{JSON.stringify lockDir}"
			console.error "This shouldn't ever happen."

			# But we don't want to lock the user out of this object forever.
			# So we'll just delete the lock and continue on.
			console.error "Continuing on assumption that lock is stale."

			# isStale = true
			cb null, true, null

	_renew: (cb) ->
		if @_hasLeaseExpired()
			clearInterval @_renewInterval
			@_renewInterval = null
			@_released = true
			cb new Error "cannot renew, lease already expired"
			return

		Lock._writeExpiryTimestamp @_path, @_tmpDirPath, (err, expiryTimestamp) =>
			if err
				cb err
				return

			# Actual expiry time is the latest of all expiry times written,
			# so we only need to update the next expiry time if expiryTimestamp
			# is later.
			if Moment(expiryTimestamp, TimestampFormat).isAfter Moment(@_nextExpiryTimestamp, TimestampFormat)
				@_nextExpiryTimestamp = expiryTimestamp

			cb()

	release: (cb=(->)) ->
		# If lease has expired
		if @_hasLeaseExpired() or @_released
			process.nextTick ->
				cb()
			return

		clearInterval @_renewInterval
		@_renewInterval = null
		@_released = true

		Atomic.deleteDirectory @_path, @_tmpDirPath, (err) ->
			if err
				cb new IOError err
				return

			cb()

	_hasLeaseExpired: ->
		return Moment(@_nextExpiryTimestamp, TimestampFormat).isBefore Moment()

	@_readExpiryTimestamp: (lockDir, cb) ->
		Fs.readdir lockDir, (err, fileNames) ->
			if err
				cb new IOError err
				return

			expiryTimestamps = Imm.List(fileNames)
			.filter (fileName) ->
				return fileName[0...'expire-'.length] is 'expire-'
			.map (fileName) ->
				return Moment(fileName['expire-'.length...], TimestampFormat)
			.sort()

			if expiryTimestamps.size is 0
				cb null, null
				return

			result = expiryTimestamps.last().format(TimestampFormat)

			# Read metadata and return
			Fs.readFile lockDir+"/metadata", (err, data) ->
				if err
					cb new IOError
					return

				# Return parsed metadata object
				metadata = JSON.parse(data)

				cb null, result, metadata

	@_writeExpiryTimestamp: (lockDir, tmpDirPath, cb) ->
		expiryTimestamp = Moment().add(leaseTime, 'ms').format(TimestampFormat)
		expiryTimestampFile = Path.join(lockDir, 'expire-' + expiryTimestamp)

		fileData = new Buffer('expiry-time', 'utf8') # some filler data

		Atomic.writeBufferToFile expiryTimestampFile, tmpDirPath, fileData, (err) ->
			if err
				cb new IOError err
				return

			cb null, expiryTimestamp

	@_writeMetadata: (lockDir, tmpDirPath, cb) ->
		metadataFile = Path.join(lockDir, 'metadata')

		metadata = new Buffer(JSON.stringify {
			userName: global.ActiveSession.userName
		}, 'utf8')

		Atomic.writeBufferToFile metadataFile, tmpDirPath, metadata, (err) ->
			if err
				cb new IOError err
				return

			cb null

class LockInUseError extends CustomError
Lock.LockInUseError = LockInUseError

module.exports = Lock
