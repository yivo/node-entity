registry  = require 'yivo-node-registry'
Db        = require 'mysql-activerecord'
_         = require 'lodash'
log       = require('yivo-node-log').create 'Entity'

db = null

unless _.isFunction (->).sync
  log.warn 'node-sync is not installed. Synchronous methods will cause errors'

isFalsy = (value) ->
  value is undefined or value is null

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

  isSaved: -> !!@id

  isDirty: -> _.isObject @__changes

  set: (arg, newValue) ->
    if _.isObject arg
      @set attrName, newValue for own attrName, newValue of arg
      return @

    attrName = arg
    if newValue isnt @attributes[attrName]
      @__changes = {} unless @isDirty()
      @__changes[attrName] = newValue

    @attributes[attrName] = newValue
    @

  get: (attrName) -> @attributes[attrName]

  serialize: ->
    _.extend id: @id, @attributes

  querySerialize: () ->
    result = _.pick @attributes, @constructor.attributes
    @querySerializeFinale result

  querySerializeChanges: ->
    return unless @isDirty()
    result = _.pick @__changes, @constructor.attributes
    @querySerializeFinale result

  querySerializeFinale: (result) ->
    defaults = @constructor.defaults

    if _.isObject defaults
      for own attrName, attrValue of defaults
        result[attrName] = attrValue if isFalsy result[attrName]

    delete result.id
    is_deleted = @attributes.is_deleted
    is_deleted = no if isFalsy is_deleted
    result.is_deleted = is_deleted
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
    @__changes = null
    @

  remove: (cb) ->
    @set 'is_deleted', yes
    @save cb

  removeSync: ->
    @set 'is_deleted', yes
    @saveSync()

  __insert: (cb) ->
    @db().insert @tableName(), @querySerialize(), (err, o) =>
      unless err
        @id = o.insertId
        @__changes = null
      cb err, o if _.isFunction cb

  __update: (cb) ->
    tbl = @tableName()
    @db().where(id: @id).update tbl, @querySerializeChanges(), (err, o) =>
      @__changes = null unless err
      cb err, o if _.isFunction cb

  __insertSync: ->
    [o] = @db().insert.sync @db(), @tableName(), @querySerialize()
    @id = o.insertId

  __updateSync: ->
    tbl = @tableName()
    @db().where(id: @id).update.sync @db(), tbl, @querySerialize()

  @db: ->
    db || (db = new Db.Adapter registry.get('db'))

  @preprocessClassVariables: ->
    return if @__preprocessed
    @attributes = @attributes.split(@rAttributeDelimiter) if _.isString @attributes
    @__preprocessed = yes

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