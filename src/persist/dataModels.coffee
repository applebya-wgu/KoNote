# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Joi = require 'joi'
Mkdirp = require 'mkdirp'
Path = require 'path'

ApiBuilder = require './apiBuilder'
{IdSchema, TimestampFormat} = require './utils'

dataModelDefinitions = [
	{
		name: 'clientFile'
		collectionName: 'clientFiles'
		isMutable: true
		indexes: [
			['clientName', 'first']
			['clientName', 'middle']
			['clientName', 'last']
			['recordId']
		]
		schema: Joi.object().keys({
			clientName: Joi.object().keys({
				first: Joi.string()
				middle: Joi.string().allow('')
				last: Joi.string()
			})
			recordId: [Joi.string(), '']
			plan: Joi.object().keys({
				sections: Joi.array().items(
					Joi.object().keys({
						id: IdSchema
						name: Joi.string()
						targetIds: Joi.array().items(
							IdSchema
						)
					})
				)
			})
		})
		children: [
			{
				name: 'progEvent'
				collectionName: 'progEvents'
				isMutable: true
				indexes: [['relatedProgNoteId'], ['status']]
				schema: Joi.object().keys({					
					title: Joi.string()					
					description: Joi.string().allow('')			
					startTimestamp: Joi.date().format(TimestampFormat).raw()
					endTimestamp: Joi.date().format(TimestampFormat).raw().allow('')
					status: ['default', 'cancelled']
					statusReason: Joi.string().optional()
					typeId: IdSchema.allow('')
					relatedProgNoteId: IdSchema
					relatedElement: Joi.object().keys({
						id: IdSchema
						type: ['progNoteUnit', 'planSection', 'planTarget']						
					}).allow('')					
				})
			}
			{
				name: 'planTarget'
				collectionName: 'planTargets'
				isMutable: true
				schema: Joi.object().keys({
					name: Joi.string()
					notes: Joi.string()
					metricIds: Joi.array().items(
						IdSchema
					)
				})
			}
			{
				name: 'progNote'
				collectionName: 'progNotes'
				isMutable: true
				indexes: [['timestamp'], ['backdate']]
				schema: [
					Joi.object().keys({
						type: 'basic' # aka "Quick Notes"
						status: ['default', 'cancelled']
						statusReason: Joi.string().optional()
						notes: Joi.string()
						backdate: Joi.date().format(TimestampFormat).raw().allow('')
					})
					Joi.object().keys({
						type: 'full'
						status: ['default', 'cancelled']
						statusReason: Joi.string().optional()
						templateId: IdSchema
						backdate: Joi.date().format(TimestampFormat).raw().allow('')
						units: Joi.array().items(
							[
								Joi.object().keys({
									id: IdSchema
									type: 'basic'
									name: Joi.string()
									notes: Joi.string().allow('')
									metrics: Joi.array().items(
										Joi.object().keys({
											id: IdSchema
											name: Joi.string()
											definition: Joi.string()
											value: Joi.string().allow('')
										})
									)
								})
								Joi.object().keys({
									id: IdSchema
									type: 'plan'
									name: Joi.string()
									sections: Joi.array().items(
										Joi.object().keys({
											id: IdSchema
											name: Joi.string()
											targets: Joi.array().items(
												Joi.object().keys({
													id: IdSchema
													name: Joi.string()
													notes: Joi.string().allow('')
													metrics: Joi.array().items(
														Joi.object().keys({
															id: IdSchema
															name: Joi.string()
															definition: Joi.string()
															value: Joi.string().allow('')
														})
													)
												})
											)
										})
									)
								})
							]
						)
					})
				]
			}
		]
	}
	{
		name: 'progNoteTemplate'
		collectionName: 'progNoteTemplates'
		isMutable: true
		indexes: [['name']]
		schema: Joi.object().keys({
			name: Joi.string()
			sections: Joi.array().items(
				[
					Joi.object().keys({
						type: 'basic'
						name: Joi.string()
						metricIds: Joi.array().items(
							IdSchema
						)
					})
					Joi.object().keys({
						type: 'plan'
						name: Joi.string()
					})
				]
			)
		})
	}

	{
		name: 'metric'
		collectionName: 'metrics'
		isMutable: false
		indexes: [['name']]
		schema: Joi.object().keys({
			name: Joi.string()
			definition: Joi.string()
		})
	}

	{
		name: 'program'
		collectionName: 'programs'
		isMutable: true
		indexes: [['name'], ['colorKeyHex']]
		schema: Joi.object().keys({
			name: Joi.string()
			description: Joi.string()
			colorKeyHex: Joi.string().regex(/^#[A-Fa-f0-9]{6}/)
		})
	}

	{
		name: 'eventType'
		collectionName: 'eventTypes'
		isMutable: true
		schema: Joi.object().keys({
			name: Joi.string()
			description: Joi.string()
			colorKeyHex: Joi.string().regex(/^#[A-Fa-f0-9]{6}/)
			status: ['default', 'cancelled']
		})
	}

	# Link a clientFileId to 1 or more programIds
	{
		name: 'clientFileProgramLink'
		collectionName: 'clientFileProgramLinks'
		isMutable: true
		indexes: [['status'], ['clientFileId'], ['programId']]
		schema: Joi.object().keys({
			clientFileId: IdSchema
			programId: IdSchema
			status: ['enrolled', 'unenrolled']
		})
	}
]

getApi = (session) ->
	ApiBuilder.buildApi session, dataModelDefinitions

# TODO This shouldn't be here, since it's derived from the data model, not part of it
setUpDataDirectory = (dataDir, cb) ->
	# Set up top-level directories
	Async.series [
		(cb) ->
			Async.each dataModelDefinitions, (modelDef, cb) ->
				Mkdirp Path.join(dataDir, modelDef.collectionName), cb
			, cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_tmp'), cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_users'), cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_locks'), cb
	], cb

module.exports = {getApi, setUpDataDirectory}
