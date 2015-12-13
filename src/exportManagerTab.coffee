# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
_ = require 'underscore'
Imm = require 'immutable'
Persist = require './persist'
Fs = require 'fs'
Archiver = require 'archiver'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Moment = require 'moment'

	Config = require('./config')
	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)	
	{FaIcon} = require('./utils').load(win)

	ExportManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		
		componentDidMount: ->
			# Register listeners for full data backup
			timestamp = Moment().format('YYYY-MM-DD')
			fileName = "konote-backup-#{timestamp}.zip"

			$chooser = $(@refs.inputDialog.getDOMNode())
			.attr("nwsaveas", fileName)
			.on('change', (event) => @_saveDataDirectory event.target.value)
		
		render: ->
			return R.div({className: 'exportManagerTab'},
				R.div({className: 'header'},
					R.h1({}, "Export Data")
				)
				R.div({className: 'main'},
					R.button({
						className: 'btn btn-primary btn-lg'
						onClick: @_exportMetrics
					}, "Export Metrics")
				)
				R.input({
					className: 'hidden'
					type: 'file'
					ref: 'inputDialog'
				})
				R.div({className: 'main'},
					R.button({
						className: 'btn btn-primary btn-lg'
						onClick: @_exportDataDirectory
					}, "Backup Data")
				)
			)

		_exportMetrics: ->
			metrics = null

			# Map over client files
			Async.map @props.clientFileHeaders.toArray(), (clientFile, cb) ->

				metricsResult = Imm.List()

				metricDefinitionHeaders = null
				metricDefinitions = null
				progNoteHeaders = null
				progNotes = null				
				clientFileId = clientFile.get('id')

				Async.series [
					# List metric definition headers
					(cb) =>
						ActiveSession.persist.metrics.list (err, results) ->
							if err
								cb err
								return

							metricDefinitionHeaders = results
							cb()

					# Retrieve all metric definitions
					(cb) =>
						Async.map metricDefinitionHeaders.toArray(), (metricHeader, cb) ->
							ActiveSession.persist.metrics.read metricHeader.get('id'), cb
						, (err, results) ->
							if err
								cb err
								return

							metricDefinitions = Imm.List results
							cb()

					# List progNote headers
					(cb) =>
						ActiveSession.persist.progNotes.list clientFileId, (err, results) ->
							if err
								cb err
								return

							progNoteHeaders = results
							cb()

					# Retrieve progNotes
					(cb) =>
						Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) ->
							ActiveSession.persist.progNotes.read clientFileId, progNoteHeader.get('id'), cb
						, (err, results) ->
							if err
								cb err
								return

							progNotes = Imm.List results
							console.info "progNotes", progNotes.toJS()
							cb()

					# Filter out metrics, apply definitions
					(cb) =>
						Async.map progNotes.toArray(), (progNote, cb) ->
							progNote.get('sections').map (note) ->

							cb null, progNote
						, (err, results) ->
							if err
								cb err
								return

							console.info "Results", results
							cb()
						
				], cb
			, (err) ->
				if err
					CrashHandler.handle err
					return

				console.info "Done!"
				
		_exportDataDirectory: ->
			chooser = React.findDOMNode(@refs.inputDialog)
			chooser.click()
			
		_saveDataDirectory: (path) ->
			if path.length > 1
				output = Fs.createWriteStream(path);
				archive = Archiver('zip');

				output.on 'close', ->
					backupSize = (archive.pointer()/1000).toFixed(2)
					if backupSize > 1
						Bootbox.alert {
							title: "Backup Successful (#{backupSize}KB)"
							message: "Saved to: #{path}"
						}
					else
						Bootbox.alert {
							title: "Error"
							message: "Saved file size less than expected (#{backupSize}KB)."
						}
				.on 'error', (err) ->
					CrashHandler.handle err

				archive.on 'error', (err) ->
					CrashHandler.handle err

				archive.pipe(output)
				archive.bulk [{
					expand: true
					cwd: Config.dataDirectory
					src: ['**/*']
					dest: 'data'
				}]
			
				archive.finalize()

	return ExportManagerTab

module.exports = {load}