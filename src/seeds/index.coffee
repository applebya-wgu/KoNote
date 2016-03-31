Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'
Moment = require 'moment'

{Users, Persist, generateId} = require '../persist'
Create = require './create'

generateClientFiles = (quantity, metrics, cb) ->
	clientFile = null
	planTarget = null

	Async.mapSeries [1...quantity], (quantityPosition, cb) ->
		console.log "About to generate clientFile ##{quantityPosition}"

		Async.series [
			# Create the empty clientFile
			(cb) ->
				Create.clientFile (err, result) ->
					if err
						cb err
						return

					clientFile = result
					console.log "Created clientFile", clientFile.toJS()
					cb()

			# Create a single target
			(cb) ->
				Create.planTarget clientFile, metrics, (err, result) ->
					if err
						cb err
						return

					planTarget = result
					console.log "Created planTarget", planTarget.toJS()
					cb()

			# Apply the target to a section, apply to clientFile, save
			(cb) ->
				section = {
					id: generateId()
					name: "Aggression Section"
					targetIds: [planTarget.get('id')]
				}

				sections = [section]

				console.log "Sections to add:", sections

				clientFile = clientFile.setIn(['plan', 'sections'], sections)

				global.ActiveSession.persist.clientFiles.createRevision clientFile, (err, result) ->
					if err
						cb err
						return

					clientFile = result
					console.log "Modified clientFile with sections:", clientFile.toJS()
					cb()

		], (err) ->
			if err
				cb err
				return

			console.log "Done with clientFile ##{quantityPosition}"
			cb(null, clientFile)

	, (err, results) ->
		if err
			cb err
			return

		clientFiles = Imm.List(results)
		cb(null, clientFiles)


runSeries = ->
	clientFiles = null
	programs = null
	links = null
	metrics = null
	eventTypes = null
	accounts = null
	quickNotes = null
	planTargets = null

	Async.series [
		(cb) ->
			Create.accounts 0, (err, results) ->
				if err
					cb err
					return

				accounts = results
				cb()

		(cb) ->
			Create.programs 2, (err, results) ->
				if err
					cb err
					return

				programs = results
				cb()		

		(cb) ->
			Create.eventTypes 1, (err, results) ->
				if err
					cb err
					return

				eventTypes = results
				cb()		

		(cb) ->
			Create.metrics 4, (err, results) ->
				if err
					cb err
					return

				metrics = results
				cb()

		(cb) ->
			generateClientFiles 10, metrics, (err, results) ->
				if err
					cb err
					return

				clientFiles = results
				console.log "DONE! clientFiles generated:", clientFiles.toJS()
				cb()

		# (cb) ->
		# 	Async.map programs.toArray(), (program, cb) ->
		# 		Create.clientFileProgramLinks clientFiles, program, (err, result) ->
		# 			if err 
		# 				cb err
		# 				return

		# 			cb null, Imm.List(result)
		# 	, (err, result) ->
		# 		if err
		# 			cb err
		# 			return

		# 		links = Imm.List(result)
		# 		cb()


		# (cb) ->
		# 	#should add a single planTarget to each client file
		# 	createPlanTargets clientFiles, metrics (err, result) ->
		# 		if err
		# 			cb err
		# 			return

		# 		planTargets = result
		# 		cb()



	], (err) ->
		if err
			console.error err
			return




module.exports = {
	
	runSeries

}

