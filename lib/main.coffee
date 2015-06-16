memwatch = require 'memwatch-next'
{CompositeDisposable, Disposable} = require 'atom'

module.exports =
  config:
    maxDisposables:
      type: 'integer'
      default: 100
    maxMarkers:
      type: 'integer'
      default: 100

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @handleEvents(editor)

    @commandSubscription = atom.commands.add 'atom-workspace',
      'leak-detector:start': => @start()

  deactivate: ->
    @subscriptions?.dispose()
    @subscriptions = null
    @commandSubscription?.dispose()
    @commandSubscription = null

  handleEvents: (editor) ->
    {displayBuffer} = editor

    markerCreatedSubscription = displayBuffer.onDidCreateMarker ->
      makersLength = Object.keys(displayBuffer.markers).length
      if makersLength > atom.config.get('leak-detector.maxMarkers')
        obj = {}
        Error.captureStackTrace(obj, CompositeDisposable::add)
        message = "possible DisplayBuffer memory leak detected. #{makersLength} markers added."
        atom.notifications.addError(message, {detail: obj.stack, dismissable: true})
      return

    editorDestroyedSubscription = editor.onDidDestroy =>
      markerCreatedSubscription.dispose()
      editorDestroyedSubscription.dispose()

      @subscriptions.remove(markerCreatedSubscription)
      @subscriptions.remove(editorDestroyedSubscription)

    @subscriptions.add(markerCreatedSubscription)
    @subscriptions.add(editorDestroyedSubscription)

  start: ->
    @leakSubscriptions = new CompositeDisposable
    @leakSubscriptions.add(@wrapCompositeDisposable())

    onLeakCallback = (info) => @onLeak(info)
    memwatch.on('leak', onLeakCallback)
    @leakSubscriptions.add(new Disposable( ->
      memwatch.removeListener('leak', onLeakCallback)
    ))

    @commandSubscription?.dispose()
    @commandSubscription = atom.commands.add 'atom-workspace',
      'leak-detector:stop': => @stop()

  stop: ->
    @leakSubscriptions.dispose()
    @leakSubscriptions = null

    @commandSubscription?.dispose()
    @commandSubscription = atom.commands.add 'atom-workspace',
      'leak-detector:start': => @start()

  onLeak: (info) ->
    console.warn 'Leak Detection', info

  wrapCompositeDisposable: ->
    add = CompositeDisposable::add
    CompositeDisposable::add = ->
      add.apply(this, arguments)
      if @disposables.size > atom.config.get('leak-detector.maxDisposables')
        obj = {}
        Error.captureStackTrace(obj, CompositeDisposable::add)
        message = "possible CompositeDisposable memory leak detected. #{@disposables.size} disposables added."
        atom.notifications.addError(message, {detail: obj.stack, dismissable: true})
      return

    new Disposable ->
      CompositeDisposable::add = add
