# Here, we kick off the appropriate page rendering code based on what page ID
# is specified in the URL.
#
# Special care is taken to provide the correct "window" object.  JS code that
# has been require()'d can't rely on `window` being set to the correct object.
# It seems that only code that was included via a <script> tag can rely on
# `window` being set correctly.

init = (win) ->
	Backbone = require 'backbone'
	QueryString = require 'querystring'

	CrashHandler = require('./crashHandler').load(win)
	Gui = win.require 'nw.gui'

	# Handle any uncaught errors.
	# Generally, errors should be passed directly to CrashHandler instead of
	# being thrown so that the error brings down only one window.  Errors that
	# reach this event handler will bring down the entire application, which is
	# usually less desirable.
	process.on 'uncaughtException', (err) ->
		CrashHandler.handle err

	win.jQuery ->
		# Pull any parameters out of the URL
		urlParams = QueryString.parse win.location.search.substr(1)

		# Decide what to render based on the page parameter
		# URL would look something like `.../main.html?page=client`
		switch urlParams.page
			when 'login'
				require('./loginPage').load(win, urlParams)
			when 'clientSelection'
				require('./clientSelectionPage').load(win, urlParams)
			when 'clientFile'
				require('./clientFilePage').load(win, urlParams)
			when 'newProgNote'
				require('./newProgNotePage').load(win, urlParams)
			else
				require('./loginPage').load(win, urlParams)

		win.document.addEventListener 'keyup', (event) ->
			# If Ctrl-Shift-J
			if event.ctrlKey and event.shiftKey and event.which is 74
				Gui.Window.get(win).showDevTools()
		, false

		win.document.addEventListener 'keyup', (event) ->
			# If Ctrl-R
			if event.ctrlKey and (not event.shiftKey) and event.which is 82
				win.location.reload(true)
		, false

		win.document.addEventListener 'keyup', (event) ->
			# If Ctrl-W
			if event.ctrlKey and (not event.shiftKey) and event.which is 87
				Gui.Window.get(win).close()
		, false

module.exports = {init}
