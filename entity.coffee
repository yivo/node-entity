registry  = require 'yivo-node-registry'
Db        = require 'mysql-activerecord'
_         = require 'lodash'

db = null

class Entity

  @attributes: null
  @defaults: null
  @tableName: null
  @rAttributeDelimiter: /[\s,]+/

  constructor: (attributes) ->
    @constructor.preprocessClassVariables()
    attributes = {} unless _.isObject attributes
    @attributes = attributes
    @id = @attributes.id
    delete @attributes.id

  tableName: ->
    @constructor.tableName

  db: -> @constructor.db()

  isSaved: ->
    !!@id

  isDirty: ->
    @__isDirty

  set: (arg, newValue) ->
    if _.isObject arg
      @set attrName, newValue for own attrName, newValue of arg
      return @

    attrName = arg
    @__isDirty ||= newValue isnt @attributes[attrName]
    @attributes[attrName] = newValue
    @

  get: (attrName) ->
    @attributes[attrName]

  serialize: ->
    _.extend id: @id, @attributes

  querySerialize: ->
    result = _.pick @attributes, @constructor.attributes
    defaults = @constructor.defaults

    if _.isObject defaults
      for own attrName, attrValue of defaults
        result[attrName] = attrValue unless result[attrName]?

    delete result.id
    result

  save: (cb) ->
    if not @isSaved()
      @__insert cb
    else if @isDirty()
      @__update cb
    @

  saveSync: ->
    if not @isSaved()
      @__insertSync()
    else if @isDirty()
      @__updateSync()
    @__isDirty = false
    @

  remove: (cb) ->
    @set 'is_deleted', true
    @save cb

  removeSync: ->
    @set 'is_deleted', true
    @saveSync()

  __insert: (cb) ->
    db.insert @tableName(), @querySerialize(), (err, o) =>
      unless err
        @id = o.insertId
        @__isDirty = false
      cb err, o if _.isFunction cb

  __update: (cb) ->
    tbl = @tableName()
    db.where(id: @id).update tbl, @querySerialize(), (err, o) =>
      @__isDirty = not err
      cb err, o if _.isFunction cb

  __insertSync: ->
    [o] = db.insert.sync db, @tableName(), @querySerialize()
    @id = o.insertId

  __updateSync: ->
    tbl = @tableName()
    db.where(id: @id).update.sync db, tbl, @querySerialize()

  @db: ->
    db || (db = new Db.Adapter registry.get('db'))

  @preprocessClassVariables: ->
    return if @__preprocessed
    @attributes = @attributes.split(@rAttributeDelimiter) if _.isString @attributes
    @__preprocessed = true

  @newSelect: ->
    select = @db().select ['id'].concat(@attributes)
    select.where 'is_deleted = 0'
    select

  @pullSelect: ->
    select = @select || @newSelect()
    @select = null
    select

  @scope: (name, rule) ->
    @[name] = (args...) ->
      @where if _.isFunction(rule) then rule args... else rule
      @

  @where: (args...) ->
    @select ||= @newSelect()
    @select.where args...
    @

  @order: (attrName, direction = 'asc') ->
    @select ||= @newSelect()
    @select.order_by(attrName + ' ' + direction)
    @

  @limit: (limit, offset) ->
    @select ||= @newSelect()
    @select.limit limit, offset
    @

  @many: (cb) ->
    @pullSelect().get @tableName, (err, results) =>
      if err then results = []
      else results = (new @(result) for result in results)
      cb err, results
    @

  @manySync: ->
    select = @pullSelect()
    [results] = select.get.sync select, @tableName
    (new @(result) for result in results)

  @one: (cb) ->
    @limit 1
    @pullSelect().get @tableName, (err, results) =>
      if not err and results[0] then result = new @(results[0])
      cb err, result
    @

  @oneSync: ->
    @limit 1
    select = @pullSelect()
    [results] = select.sync select, @tableName
    new @(results[0]) if results[0]

  @byId: (id, cb) ->
    @where(id: id).limit(1).one(cb) if id

  @oneSync: (id) ->
    @where(id: id).limit(1).oneSync() if id

module.exports = Entity