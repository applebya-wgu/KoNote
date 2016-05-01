# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Async = require 'async'

Config = require '../config'
Persist = require '../persist'
Term = require '../term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('../crashHandler').load(win)
	Dialog = require('../dialog').load(win)
	Spinner = require('../spinner').load(win)

	ModifyTargetStatusDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.statusReasonField.focus()

		getInitialState: ->
			return {statusReason: ''}

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Change #{Term 'Target'} Status"
				onClose: @props.onClose
			},
				R.div({className: 'cancelProgNoteDialog'},
					R.div({className: 'alert alert-warning'},
						"This will change the status of the #{Term 'target'}"
					)
					R.div({className: 'form-group'},
						R.label({}, "Reason for status change:"),
						R.textarea({
							className: 'form-control'
							style: {minWidth: 350, minHeight: 100}
							ref: 'statusReasonField'
							onChange: @_updateStatusReason
							value: @state.statusReason
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
						}, "Confirm")
					)
				)
			)

		_updateStatusReason: (event) ->
			@setState {statusReason: event.target.value}

		_submit: ->
			@refs.dialog.setIsLoading true

			revisedPlanTarget = @props.target
			.set('status', @props.newStatus)
			.set('statusReason', @state.statusReason)

			ActiveSession.persist.planTargets.createRevision revisedPlanTarget, (err, updatedPlanTarget) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Persist will trigger an event to update the UI
				@props.onSuccess()				
				

	return ModifyTargetStatusDialog

module.exports = {load}
