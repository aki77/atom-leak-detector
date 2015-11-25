{CompositeDisposable, Disposable} = require 'atom'

module.exports =
  config:
    maxDisposables:
      order: 1
      type: 'integer'
      default: 200
    maxMarkers:
      order: 2
      type: 'integer'
      default: 200
    MaxPanels:
      order: 3
      type: 'integer'
      default: 20
    autoRun:
      order: 10
      type: 'boolean'
      default: false
      description: 'only in development mode (Requirement: auto-run package)'

  activate: (state) ->
    @commandSubscription = atom.commands.add 'atom-workspace',
      'leak-detector:start': => @start()

  deactivate: ->
    @leakSubscriptions?.dispose()
    @leakSubscriptions = null
    @commandSubscription?.dispose()
    @commandSubscription = null

  handleEvents: (editor) ->
    {displayBuffer} = editor

    markerCreatedCallback =  ->
      makersLength = displayBuffer.getMarkerCount()
      if makersLength > atom.config.get('leak-detector.maxMarkers')
        obj = {}
        Error.captureStackTrace(obj, markerCreatedCallback)
        message = "possible DisplayBuffer memory leak detected. #{makersLength} markers added."
        atom.notifications.addError(message, {detail: obj.stack, dismissable: true})
      return
    markerCreatedSubscription = displayBuffer.onDidCreateMarker(markerCreatedCallback)

    editorDestroyedSubscription = editor.onDidDestroy =>
      markerCreatedSubscription.dispose()
      editorDestroyedSubscription.dispose()

      @leakSubscriptions.remove(markerCreatedSubscription)
      @leakSubscriptions.remove(editorDestroyedSubscription)

    @leakSubscriptions.add(markerCreatedSubscription)
    @leakSubscriptions.add(editorDestroyedSubscription)

  start: ->
    @leakSubscriptions = new CompositeDisposable
    @leakSubscriptions.add(@wrapCompositeDisposable())
    @leakSubscriptions.add(@watchPanels())
    @leakSubscriptions.add(atom.workspace.observeTextEditors (editor) =>
      @handleEvents(editor)
    )

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
      if @disposables?.size > atom.config.get('leak-detector.maxDisposables')
        obj = {}
        Error.captureStackTrace(obj, CompositeDisposable::add)
        message = "possible CompositeDisposable memory leak detected. #{@disposables.size} disposables added."
        atom.notifications.addError(message, {detail: obj.stack, dismissable: true})
      return

    new Disposable ->
      CompositeDisposable::add = add

  watchPanels: ->
    addedPanelCallback = ->
      panelCount = @getPanels().length
      if panelCount > atom.config.get('leak-detector.maxPanels')
        obj = {}
        Error.captureStackTrace(obj, addedPanelCallback)
        message = "possible PanelContainer panels leak detected. #{panelCount} panels added."
        atom.notifications.addError(message, {detail: obj.stack, dismissable: true})
      return

    subscriptions = new CompositeDisposable
    for location, container of atom.workspace.panelContainers
      subscriptions.add(container.onDidAddPanel(addedPanelCallback.bind(container)))

    subscriptions

  activateConfig: ->
    pack = atom.packages.getActivePackage('auto-run')
    return unless pack

    autoRun = pack.mainModule.provideAutoRun()
    autoRun.registerCommand(
      keyPath: 'leak-detector.autoRun'
      command: 'leak-detector:start'
      options:
        devMode: true
    )
