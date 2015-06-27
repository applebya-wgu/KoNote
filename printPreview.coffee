# Print preview page receives data from the printButton's data,
# and matches printing components with the type(s) of data received

Imm = require 'immutable'
Moment = require 'moment'

Config = require './config'
Persist = require './persist'

load = (win, {dataSet}) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	MetricWidget = require('./metricWidget').load(win)
	{FaIcon,renderLineBreaks, renderName, renderFileId, showWhen} = require('./utils').load(win)
	{timeoutListeners} = require('./timeoutDialog').load(win)

	do ->
		console.log "Print Data:", JSON.parse(dataSet)
		printDataSet = Imm.fromJS JSON.parse(dataSet)

		init = ->
			render()
			registerListeners()

		process.nextTick init

		render = ->
			React.render new PrintPreview({
				printDataSet
			}), $('#container')[0]

		registerListeners = ->
			timeoutListeners()

	PrintPreview = React.createFactory React.createClass
		componentDidMount: ->
			# Without timeout, print() triggers before DOM renders
			setTimeout ->
				win.print()
			, 500

		render: ->
			R.div({className: 'printPreview'},				
				(@props.printDataSet.map (printObj) =>					
					clientFile = printObj.get('clientFile')
					data = printObj.get('data')
					title = null

					R.div({className: 'printObj'},
						PrintHeader({
							data
							format: printObj.get('format')
							clientFile: clientFile
						})
						switch printObj.get('format')
							when 'progNote'
								switch data.get('type')
									when 'basic'
										BasicProgNoteView({
											progNote: data
											clientFile
										})
									when 'full'
										FullProgNoteView({
											progNote: data
											clientFile
										})
									else
										throw new Error "Unknown progNote type: #{progNote.get('type')}"
							when 'plan'
								SinglePlanView({
									title: "Care Plan"
									plan: data
									clientFile
								})
							else
								throw new Error "Unknown print-data type: #{setType}"
					)
				).toJS()...
			)


	PrintHeader = React.createFactory React.createClass
		render: ->
			R.div({className: 'header'},
				R.div({className: 'leftSide'},
					R.h1({className: 'title'},						
						FaIcon('pencil-square-o')
						switch @props.format
							when 'progNote' then "Progress Note"
							when 'plan' then "Care Plan"
					)
					R.h3({className: 'clientName'}, 
						renderName @props.clientFile.get('clientName')
					)
					R.span({className: 'clientRecordId'},
						renderFileId @props.clientFile.get('recordId')
					)
				)
				R.div({className: 'rightSide'},
					R.img({
						className: 'logo'
						src: 'customer-logo-lg.png'
					})
					R.ul({},
						R.li({}, 
							FaIcon('user')
							"Authored by: "
							# TODO: Include user's full name + username ("Andrew Appleby (aappleby)")
							R.span({className: 'author'}, @props.data.get('author'))
						)
						R.li({className: 'date'},
							Moment(@props.data.get('timestamp'), Persist.TimestampFormat)
							.format 'MMMM D, YYYY [at] HH:mm'
						)
					)
					R.ul({},
						R.li({},
							FaIcon('print')
							"Printed by: "
							# TODO: Include user's full name + username ("Andrew Appleby (aappleby)")
							R.span({className: 'author'}, global.ActiveSession.userName)
						)
						R.li({className: 'date'},
							Moment().format 'MMMM D, YYYY [at] HH:mm'
						)
					)
				)
			)

	BasicProgNoteView = React.createFactory React.createClass
		render: ->			
			R.div({className: 'basic progNote'},				
				R.div({className: 'notes'},
					renderLineBreaks @props.progNote.get('notes')
				)
			)

	FullProgNoteView = React.createFactory React.createClass
		render: ->
			R.div({className: 'full progNote'},
				R.div({className: 'sections'},
					(@props.progNote.get('sections').map (section) =>
						switch section.get('type')
							when 'basic'
								R.div({className: 'basic section', key: section.get('id')},
									R.h1({
										className: 'name'
									},
										section.get('name')
									)
									R.div({className: "empty #{showWhen section.get('notes').length is 0}"},
										'(blank)'
									)
									R.div({className: 'notes'},
										renderLineBreaks section.get('notes')
									)
									R.div({className: 'metrics'},
										(section.get('metrics').map (metric) =>
											MetricWidget({
												isEditable: false
												key: metric.get('id')
												name: metric.get('name')
												definition: metric.get('definition')
												value: metric.get('value')
											})
										).toJS()...
									)
								)
							when 'plan'
								R.div({className: 'plan section', key: section.get('id')},
									R.h1({className: 'name'},
										section.get('name')
									)
									R.div({className: "empty #{showWhen section.get('targets') is ''}"},
										"This section is empty because the client has no plan targets."
									)
									R.div({className: 'targets'},
										(section.get('targets').map (target) =>
											R.div({
												className: 'target'
												key: target.get('id')
											},
												R.h2({
													className: 'name'
												},
													target.get('name')
												)
												R.div({className: "empty #{showWhen target.get('notes') is ''}"},
													'(blank)'
												)
												R.div({className: 'notes'},
													renderLineBreaks target.get('notes')
												)
												R.div({className: 'metrics'},
													(target.get('metrics').map (metric) =>
														MetricWidget({
															isEditable: false
															key: metric.get('id')
															name: metric.get('name')
															definition: metric.get('definition')
															value: metric.get('value')
														})
													).toJS()...
												)
											)
										).toJS()...
									)
								)
					).toJS()...
				)
			)

module.exports = {load}