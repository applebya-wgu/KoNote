# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module implements the core operations of the persistent object store.
#
# The Persist package generates an API based on the data models it is
# configured with.  Within that API, there is an interface for each collection
# (e.g. `persist.clientFiles` or `persist.metrics`).  That interface is called
# a Collection API, i.e. an API for a specific collection.
#
# The `createCollectionApi` function generates an API for a single collection
# based on a data model (and some additional information such as the current
# session).  The `persist/apiBuilder` module uses this function on every data
# model definition.

Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
BufferEq = require 'buffer-equal-constant-time'
Fs = require 'fs'
Joi = require 'joi'
Imm = require 'immutable'
Moment = require 'moment'
Path = require 'path'

Atomic = require './atomic'
Crypto = require './crypto'

{
	IOError
	IdSchema
	ObjectNotFoundError
	TimestampFormat
	generateId
} = require './utils'

joiValidationOptions = Object.freeze {
	# I would like to set this to false, but Joi doesn't seem to support date
	# string validation without convert: true
	convert: true

	# Any properties that are not required must be explicitly marked optional.
	presence: 'required'
}

# Create an API based on the specified model definition.
#
# session: a Session object
# eventBus: the EventBus to which object mutation events should be dispatched
# context: a List of Maps.  Each Map represents an ancestor type, ordered from
# outermost (i.e. top-level) to innermost.  Example: Imm.List([
# 	Imm.Map({
# 		definition: modelDefOuter
# 		api: apiOuter
# 	})
# 	Imm.Map({
# 		definition: modelDefInner
# 		api: apiInner
# 	})
# ])
createCollectionApi = (session, eventBus, context, modelDef) ->
	childCollectionNames = Imm.List(modelDef.children).map (childDef) ->
		return childDef.collectionName

	# A directory for temp files, i.e. stuff we don't care about
	tmpDirPath = Path.join(session.dataDirectory, '_tmp')

	# Define a series of methods that this collection API will (or might) contain.
	# These methods correspond to what is documented in the wiki.
	# See the wiki for instructions on their use.

	create = (obj, cb) ->
		# The object hasn't been created yet, so it shouldn't have any of these
		# metadata fields.  If it does, it probably indicates a bug.

		if obj.has('id')
			cb new Error "new objects cannot already have an ID"
			return

		if obj.has('revisionId')
			cb new Error "new objects cannot already have a revision ID"
			return

		if obj.has('author')
			cb new Error "new objects cannot already have an author"
			return

		if obj.has('timestamp')
			cb new Error "new objects cannot already have a timestamp"
			return

		# Pull out the IDs of this object's ancestors
		# E.g. if we're creating a prognote, extract clientFileId
		contextualIds = extractContextualIds obj

		# Add metadata fields
		obj = obj
		.set 'id', generateId()
		.set 'revisionId', generateId()
		.set 'author', session.userName
		.set 'timestamp', Moment().format(TimestampFormat)

		fileNameEncryptionKey = getFileNameEncryptionKey()

		destObjDir = null
		objDir = null
		objDirOp = null

		Async.series [
			(cb) ->
				# Figure out what directory contains this collection.
				# This depends on whether this collection has a parent,
				# so pass in the contextualIds.
				getParentDir contextualIds, (err, parentDir) ->
					if err
						cb err
						return

					# Generate this object's future directory name
					fileName = createObjectFileName(obj, modelDef.indexes)
					encryptedFileName = Base64url.encode fileNameEncryptionKey.encrypt fileName

					# Generate this object's future directory path
					destObjDir = Path.join(
						parentDir
						modelDef.collectionName
						encryptedFileName
					)

					cb()
			(cb) ->
				# In order to make the operation atomic, we write to a
				# temporary object directory first, then commit it later.
				Atomic.writeDirectory destObjDir, tmpDirPath, (err, tmpObjDir, op) ->
					if err
						cb err
						return

					objDir = tmpObjDir
					objDirOp = op
					cb()
			(cb) ->
				# Create subdirs for subcollection
				Async.each modelDef.children, (child, cb) ->
					childDir = Path.join(objDir, child.collectionName)

					Fs.mkdir childDir, (err) ->
						if err
							cb new IOError err
							return

						cb()
				, cb
			(cb) ->
				# Create the first revision of this new object

				# Generate the revision file name and path
				revFileName = createRevisionFileName(obj)
				encryptedRevFileName = Base64url.encode fileNameEncryptionKey.encrypt revFileName

				# The revision file will go in the object directory
				revFilePath = Path.join(objDir, encryptedRevFileName)

				writeObjectFile obj, revFilePath, contextualIds, cb
			(cb) ->
				# Done preparing the object directory, finish the operation atomically
				objDirOp.commit cb
		], (err) ->
			if err
				cb err
				return

			# Dispatch event via event bus, notifying the app of the change
			eventBus.trigger "create:#{modelDef.name}", obj

			# Return a copy of the newly created object, complete with metadata
			cb null, obj

	list = (contextualIds..., cb) ->
		# API user must provide IDs for each of the ancestor objects,
		# otherwise, we don't know where to look
		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		collectionDir = null
		fileNames = null

		Async.series [
			(cb) ->
				# Get path to directory that contains this collection
				getParentDir contextualIds, (err, parentDir) ->
					if err
						cb err
						return

					collectionDir = Path.join(
						parentDir
						modelDef.collectionName
					)
					cb()
			(cb) ->
				# Each file in the collection dir is an object
				Fs.readdir collectionDir, (err, results) ->
					if err
						cb new IOError err
						return

					fileNames = results
					cb()
		], (err) ->
			if err
				cb err
				return

			# Decrypt/parse the file names
			result = Imm.List(fileNames)
				.filter isValidFileName
				.map (fileName) ->
					# Decrypt file name
					decryptedFileName = getFileNameEncryptionKey().decrypt(
						Base64url.toBuffer fileName
					)

					# Parse file name
					[indexValues..., id] = decodeFileName(decryptedFileName, modelDef.indexes.length + 1)

					# Prepare this entry in the results list
					result = Imm.Map({
						id: Base64url.encode id
						_dirPath: Path.join(collectionDir, fileName) # for internal use only
					})

					# Use model def to match up the indexed field names with their values
					for indexedProp, i in modelDef.indexes
						result = result.setIn indexedProp, indexValues[i].toString()

					return result

			cb null, result

	read = (contextualIds..., id, cb) ->
		# API user must provide enough IDs to figure out where this collection
		# is located.
		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		# Get the path of the object directory corresponding to this ID
		lookupObjDirById contextualIds, id, (err, objDir) ->
			if err
				cb err
				return

			# List the directory to see all revisions
			Fs.readdir objDir, (err, revisionFiles) ->
				if err
					cb new IOError err
					return

				# Object directories can also contain other collections,
				# so we need to filter those out first
				# Ensure validFileName first
				revisionFiles = revisionFiles.filter (fileName) ->
					return isValidFileName(fileName) and not childCollectionNames.contains(fileName)

				# The read method is only available to immutable collections
				if revisionFiles.length > 1
					cb new Error "object at #{JSON.stringify objDir} is immutable but has multiple revisions"
					return

				# There should always be exactly one revision
				if revisionFiles.length < 1
					# This should be impossible, because object creation is
					# implemented atomically.  If this occurs, it is likely due
					# to a failed migration.
					cb new Error "missing revisions in #{JSON.stringify objDir}"
					return

				# Get the only revision of this object
				revisionFile = revisionFiles[0]
				revisionFilePath = Path.join(objDir, revisionFile)

				# Read the only revision
				readObjectFile revisionFilePath, contextualIds, id, cb

	createRevision = (obj, cb) ->
		# The object should already have been created, so it should already
		# have an ID.
		unless obj.has('id')
			cb new Error "missing property 'id'"
			return

		# Use the model definition to determine what IDs are needed to figure
		# out where this object's collection is located.
		contextualIds = extractContextualIds obj

		# Add the relevant metadata fields
		obj = obj
		.set 'revisionId', generateId()
		.set 'author', session.userName
		.set 'timestamp', Moment().format(TimestampFormat)

		fileNameEncryptionKey = getFileNameEncryptionKey()

		objDir = null

		Async.series [
			(cb) ->
				# Find where this object's directory is located
				lookupObjDirById contextualIds, obj.get('id'), (err, result) ->
					if err
						cb err
						return

					objDir = result
					cb()
			(cb) ->
				# Encrypt a file name for this revision
				revFileName = createRevisionFileName(obj)
				encryptedRevFileName = Base64url.encode fileNameEncryptionKey.encrypt revFileName

				revFilePath = Path.join(objDir, encryptedRevFileName)

				# Write the revision to a file
				writeObjectFile obj, revFilePath, contextualIds, cb
			(cb) ->
				# When an indexed property changes, we need to rename the object directory
				# so that the change shows up when `list()` is used.

				parentDirPath = Path.dirname objDir

				# We expect this to be the object directory name when it is decrypted
				expectedDecryptedDirName = createObjectFileName(obj, modelDef.indexes)

				# Decrypt the current directory name
				currentEncryptedDirName = Path.basename objDir
				currentDecryptedDirName = fileNameEncryptionKey.decrypt(
					Base64url.toBuffer currentEncryptedDirName
				)

				# Does the current name match what we expected?
				if BufferEq(expectedDecryptedDirName, currentDecryptedDirName)
					# OK, no update needed
					cb()
					return

				# But sometimes expectations don't meet reality.

				# Take the expected dir name, encrypt it
				currentDirPath = Path.join(parentDirPath, currentEncryptedDirName)
				newDirName = Base64url.encode fileNameEncryptionKey.encrypt expectedDecryptedDirName
				newDirPath = Path.join(parentDirPath, newDirName)

				# Rename the object directory to the new encrypted name
				objDir = newDirPath
				Fs.rename currentDirPath, newDirPath, (err) ->
					if err
						cb new IOError err
						return

					cb()
		], (err) ->
			if err
				cb err
				return

			# Dispatch event via event bus to notify the rest of the app
			# about the change
			eventBus.trigger "createRevision:#{modelDef.name}", obj

			cb null, obj

	listRevisions = (contextualIds..., id, cb) ->
		# Need enough context to locate this object's collection
		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		fileNameEncryptionKey = getFileNameEncryptionKey()

		objDir = null
		revisions = null
		revObjs = null

		Async.series [
			(cb) ->
				# Locate the object's directory
				lookupObjDirById contextualIds, id, (err, result) ->
					if err
						cb err
						return

					objDir = result

					cb()
			(cb) ->
				# List the revision files inside the object dir
				Fs.readdir objDir, (err, fileNames) ->
					if err
						cb new IOError err
						return

					revisions = Imm.List(fileNames)
					.filter (fileName) ->
						# Object directories can also contain child collections.
						# These need to be filtered out.
						# Ensure validFileName first
						return isValidFileName(fileName) and not childCollectionNames.contains(fileName)
					.map (fileName) ->
						# Decrypt the revision file name
						decryptedFileName = fileNameEncryptionKey.decrypt(
							Base64url.toBuffer fileName
						)

						# Parse the revision file name, and add some fields for
						# internal use
						revision = parseRevisionFileName(decryptedFileName)
							.set('_fileName', fileName)
							.set('_filePath', Path.join(objDir, fileName))
						return revision
					# Sort the results from earliest to latest
					.sortBy (rev) -> Moment(rev.get('timestamp'), TimestampFormat)

					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, revisions

	readRevisions = (contextualIds..., id, cb) ->
		unless cb
			cb new Error "readRevisions must be provided a callback"
			return

		# Need enough information to determine where this object's collection
		# is located
		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		# List all of this object's revisions
		listRevisions contextualIds..., id, (err, revisions) ->
			if err
				cb err
				return

			# Read the revision files one-by-one
			Async.map revisions.toArray(), (rev, cb) ->
				readObjectFile rev.get('_filePath'), contextualIds, id, cb
			, (err, results) ->
				if err
					cb err
					return

				cb null, Imm.List(results)

	readLatestRevisions = (contextualIds..., id, maxRevisionCount, cb) ->
		unless cb
			throw new Error "readLatestRevisions must be provided a callback"

		# Need object IDs of any ancestor objects in order to locate this
		# object's collection
		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		if maxRevisionCount < 0
			cb new Error "maxRevisionCount must be >= 0"
			return

		# We could theoretically optimize for maxRevisionCount=0 here.
		# However, this would cause requests for non-existant objects to succeed.

		# List all of the object's revisions
		listRevisions contextualIds..., id, (err, revisions) ->
			if err
				cb err
				return

			# Only access the most recent revisions
			revisions = revisions.takeLast maxRevisionCount

			# Read only those revision files
			Async.map revisions.toArray(), (rev, cb) ->
				readObjectFile rev.get('_filePath'), contextualIds, id, cb
			, (err, results) ->
				if err
					cb err
					return

				cb null, Imm.List(results)

	# Private utility methods

	# Extract from `obj` the ID field for every ancestor object.
	#
	# Some collections exist within another object.  E.g. a collection of
	# progress notes exists inside every client file object.  Suppose we want
	# to `list()` one of those progress note collections.  In order to know
	# which progress notes folder to read, we need to know the ID of the client
	# file that contains it.  That client file is called the "parent" of the
	# collection.
	#
	# This function returns a list of the IDs needed to figure out where a
	# collection is located.  Suppose we want to access the "comments"
	# collection at `data/clientFiles/123/progNotes/234/comments/`.  This
	# function would access the object's `clientFileId` and `progNoteId`, and
	# return `["123", "234"]`.  In this example, client file 123 and prognote
	# 234 are "ancestors" of the comments collection.
	extractContextualIds = (obj) ->
		return context.map (contextEntry) ->
			contextDef = contextEntry.get('definition')
			contextIdProp = contextDef.name + 'Id'

			if obj.has(contextIdProp)
				return obj.get(contextIdProp)

			throw new Error "Object is missing field #{JSON.stringify contextIdProp}"

	# Get the path to the parent object's directory.
	# If this collection does not have a parent object, just returns the data
	# directory path.
	getParentDir = (contextualIds, cb) ->
		if Array.isArray contextualIds
			contextualIds = Imm.List(contextualIds)

		# If this collection is not a child of some object
		if contextualIds.size is 0
			# The parent directory is just the data directory
			cb null, session.dataDirectory
			return

		# Get the collection API of the parent collection
		parentApi = context.last().get('api')

		# Look up the parent object directory in the parent collection
		parentApi._lookupObjDirById contextualIds.skipLast(1), contextualIds.last(), cb

	# Get the path to the directory of an object in this collection.
	lookupObjDirById = (contextualIds, objId, cb) ->
		if contextualIds instanceof Imm.List
			contextualIds = contextualIds.toArray()

		# List all objects in this collection
		list contextualIds..., (err, objs) ->
			if err
				cb err
				return

			# Find the object we're looking for
			matches = objs.filter (obj) ->
				return obj.get('id') is objId

			if matches.size > 1
				cb new Error "multiple objects found with ID #{JSON.stringify objId}"
				return

			if matches.size < 1
				cb new ObjectNotFoundError()
				return

			# Get the only match
			match = matches.get(0)

			# Return the object directory path
			cb null, match.get('_dirPath')

	# Read the object file at the specified path.
	#
	# This function decrypts the object data, parses the JSON, and validates
	# the object against the collection schema.  The object's ID and context
	# fields are also validated for security purposes.
	readObjectFile = (path, contextualIds, id, cb) ->
		# Get this collection's schema
		schema = prepareSchema modelDef.schema, context

		Fs.readFile path, (err, encryptedObj) ->
			if err
				cb new IOError err
				return

			# Decrypt and parse JSON
			decryptedJson = session.globalEncryptionKey.decrypt encryptedObj
			obj = Imm.fromJS JSON.parse decryptedJson

			# Check that this object is where it should be
			# This is a security feature to prevent tampering
			Assert Imm.is(
				obj.get('_contextCollectionNames'),
				context.map(
					(c) -> c.get('definition').collectionName
				)
			), "found object of wrong type in collection #{modelDef.collectionName}"
			Assert Imm.is(
				obj.get('_contextIds'),
				Imm.fromJS(contextualIds)
			), "found object in wrong parent in collection #{modelDef.collectionName}"
			Assert Imm.is(
				obj.get('_collectionName'),
				modelDef.collectionName
			), "found an object from #{obj.get('_collectionName')} inside #{modelDef.collectionName}"
			Assert Imm.is(
				obj.get('id'),
				id
			), "object with ID=#{id} actually had ID=#{obj.get('id')}"
			obj = obj.delete('_contextCollectionNames')
				.delete('_contextIds')
				.delete('_collectionName')

			# Validate against the collection's schema
			validation = Joi.validate obj.toJS(), schema, joiValidationOptions

			if validation.error?
				cb validation.error
				return

			cb null, Imm.fromJS validation.value

	# Write an object file to the specified path.
	#
	# This function will encode and encrypt the object.  Before doing so,
	# however, it will add information about the object's context, and validate
	# the object against this collection's schema.
	writeObjectFile = (obj, path, contextualIds, cb) ->
		# Get this collection's schema
		schema = prepareSchema modelDef.schema, context

		# Validate object against schema
		validation = Joi.validate obj.toJS(), schema, joiValidationOptions

		if validation.error?
			process.nextTick ->
				cb validation.error
			return

		# Specify where this object belongs
		# This is a security feature to prevent tampering
		validatedObjWithContext = Imm.fromJS(validation.value)
			.set('_contextCollectionNames', context.map(
				(c) -> c.get('definition').collectionName
			))
			.set('_contextIds', contextualIds)
			.set('_collectionName', modelDef.collectionName)
			.toJS()

		# Encode as JSON and encrypt
		objJson = JSON.stringify validatedObjWithContext
		encryptedObj = session.globalEncryptionKey.encrypt objJson

		# Write the encrypted object to the specified path
		# Use an atomic operation to prevent files from being partially written
		# (or corrupted).
		Atomic.writeBufferToFile path, tmpDirPath, encryptedObj, (err) ->
			if err
				cb err
				return

			cb null, obj

	# File name encryption uses a different type of encryption key.
	# That key is generated here for convenience.
	getFileNameEncryptionKey = ->
		# Derive the weak key from globalEncryptionKey.
		# Use security level 5, i.e. 5 bytes of overhead
		# (see persist/crypto for details).
		return new Crypto.WeakSymmetricEncryptionKey(session.globalEncryptionKey, 5)

	# Build and return the actual collection API, using the previously defined methods
	result = {
		create,
		list,
		_lookupObjDirById: lookupObjDirById # private for internal use
	}

	if modelDef.isMutable
		# Only mutable collections have methods related to revisions
		result.createRevision = createRevision
		result.listRevisions = listRevisions
		result.readRevisions = readRevisions
		result.readLatestRevisions = readLatestRevisions
	else
		# Immutable collections just get the basic read method
		result.read = read

	return result

# Add metadata fields to object schema
prepareSchema = (schema, context) ->
	# The schema can be an array of possible schemas
	# (see Joi documentation)
	if Array.isArray schema
		return (prepareSchema(subschema, context) for subschema in schema)

	# We assume at this point that schema is a Joi.object()

	newKeys = {
		id: IdSchema
		revisionId: IdSchema
		timestamp: Joi.date().format(TimestampFormat).raw()
		author: Joi.string().regex(/^[a-zA-Z0-9_-]+$/)
	}

	# Each context type needs its own ID field
	context.forEach (contextEntry) ->
		# Add another entry to newKeys
		typeName = contextEntry.get('definition').name
		newKeys[typeName + 'Id'] = IdSchema

	# Extend the original set of permissible keys
	return schema.keys(newKeys)

createObjectFileName = (obj, indexes) ->
	components = []

	for index in indexes
		indexValue = obj.getIn(index, '').toString()
		components.push new Buffer(indexValue, 'utf8')

	# ID is always indexed
	# For space efficiency, we'll take advantage of the fact that IDs are
	# essentially base64url.
	components.push Base64url.toBuffer obj.get('id')

	return encodeFileName components

parseRevisionFileName = (decryptedFileName) ->
	# Revision file names are encoded the same as object directory names.
	# The only difference is that revision file names are always just
	# timestamp+revisionId, instead of having a variable number of index
	# fields.  More precisely, revision file names always have exactly two
	# components: a timestamp and a revision ID.
	[timestamp, revisionId] = decodeFileName(decryptedFileName, 2)

	return Imm.Map({
		timestamp: timestamp.toString()
		revisionId: Base64url.encode revisionId
	})

createRevisionFileName = (obj) ->
	return encodeFileName [
		new Buffer(obj.get('timestamp'), 'utf8')
		Base64url.toBuffer obj.get('revisionId') # decode revision ID to save space
	]

# Since we want to include multiple strings in a single file name, an encoding
# is needed.  Ideally, we would use JSON, but JSON is rather verbose.  Since
# the file name will be encrypted, we're able to use arbitrary bytes.  We will
# use an encoding with the following rules:
# - The strings are first encoded as bytes as per UTF-8
# - All byte values (0x00 - 0xFF) except 0x00 are output unchanged.
# - 0x00 is encoded as 0x004C (i.e. a NUL byte followed by an ascii uppercase L).
#   "L" is a mnemonic for "Literal".
# - The encoded strings are delimited by 0x0053 (i.e. a NUL byte followed by an
#   ascii uppercase S).  "S" is a mnemonic for "Separator".
#
# This ensures that any string (or even any binary string) can be encoded and
# decoded unambiguously.

encodeFileName = (components) ->
	delimiter = new Buffer([0x00, 0x53])

	result = []

	for c, i in components
		if i > 0
			result.push delimiter

		encodedComp = encodeFileNameComponent(c)
		result.push encodedComp

	return Buffer.concat result

decodeFileName = (fileName, componentCount) ->
	comps = []

	nextComp = createZeroedBuffer(fileName.length)
	nextCompOffset = 0
	i = 0
	while i < fileName.length
		# If the next byte is a special sequence
		if fileName[i] is 0x00
			# If no more bytes in the file name
			if i is (fileName.length - 1)
				# There must always be another byte following a dot
				throw new Error "file name ended early: #{fileName.toJSON()}"

			switch fileName[i+1]
				when 0x4C # "L"
					# Add literal NUL byte to component
					nextComp[nextCompOffset] = 0x00
					nextCompOffset += 1
				when 0x53 # "S"
					# Found a separator, time to start on the next component

					# Add this component to result list
					comps.push nextComp.slice(0, nextCompOffset)

					# Reset for next component
					nextComp = createZeroedBuffer(fileName.length)
					nextCompOffset = 0
				else
					throw new Error "unexpected byte sequence at #{i} in file name: #{fileName.toJSON()}"

			# Skip over the next byte, since we already handled it
			i += 2
			continue

		nextComp[nextCompOffset] = fileName[i]
		nextCompOffset += 1

		i += 1

	# Add the last component to the result list
	comps.push nextComp.slice(0, nextCompOffset)

	if comps.length isnt componentCount
		console.log fileName
		throw new Error "expected #{componentCount} parts in file name #{JSON.stringify comps}"

	return comps

# In order to support arbitrary binary strings, this method encodes 0x00 bytes
# as 0x004C.
encodeFileNameComponent = (comp) ->
	unless Buffer.isBuffer comp
		throw new Error "expected file name component to be a buffer"

	literalNulByte = new Buffer([0x00, 0x4C])

	result = []

	for i in [0...comp.length]
		# If the byte needs to be encoded specially
		if comp[i] is 0x00
			result.push literalNulByte
			continue

		# This is probably pretty inefficient...
		result.push comp.slice(i, i+1)

	return Buffer.concat result

# Check fileName against OS metadata files
isValidFileName = (fileName) ->
	return fileName not in ['.DS_Store', 'Thumbs.db']

# A convenience method.  Creates a Buffer filled with 0x00 bytes.
#
# When a Buffer is first created, its contents are leftover from whatever used
# that area of memory last, which might mean that it contains sensitive
# information.  By zeroing Buffers before use, we avoid that security risk.
createZeroedBuffer = (bufferSize) ->
	result = new Buffer(bufferSize)
	result.fill(0)
	return result

module.exports = {
	createCollectionApi
}
