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

  constructor: (attributes) ->
    attributes = {} if not _.isObject(attributes) or _.isArray(attributes)
    attributes = @filterAttributes attributes
    defaults = @constructor.defaults
    if _.isObject defaults
      for own attrName, attrValue of defaults
        attributes[attrName] = attrValue if isFalsy attributes[attrName]

    @attributes = attributes

  tableName: ->
    @constructor.tableName

  db: -> @constructor.db()

  isSaved: -> !!@attributes.id

  isDirty: -> _.isObject @__changes

  filterAttributes: (attributes) ->
    _.pick attributes, @constructor.attributes

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

  id: ->
    @attributes.id

  changes: ->
    _.clone @__changes if @isDirty()

  serialize: ->
    _.clone @attributes

  querySerialize: () ->
    @filterAttributes(@attributes)

  querySerializeChanges: ->
    @filterAttributes(@__changes) if @isDirty()

  save: (cb) ->
    if not @isSaved()
      @insert cb
    else if @isDirty()
      @update cb
    @

  saveSync: ->
    if not @isSaved()
      @insertSync()
    else if @isDirty()
      @updateSync()
    @

  remove: (cb) ->
    @set 'is_deleted', yes
    @save cb

  removeSync: ->
    @set 'is_deleted', yes
    @saveSync()

  insert: (cb) ->
    @db().insert @tableName(), @querySerialize(), (err, o) =>
      unless err
        @attributes.id = o.insertId if o and o.insertId
        @__changes = null
      cb err, o if _.isFunction cb

  update: (cb) ->
    tbl = @tableName()
    @db().where(id: @id()).update tbl, @querySerializeChanges(), (err, o) =>
      @__changes = null unless err
      cb err, o if _.isFunction cb

  insertSync: ->
    [o] = @db().insert.sync @db(), @tableName(), @querySerialize()
    @attributes.id = o.insertId if o and o.insertId
    @__changes = null

  updateSync: ->
    tbl = @tableName()
    @db().where(id: @id()).update.sync @db(), tbl, @querySerializeChanges()
    @__changes = null

  @db: ->
    db || (db = new Db.Adapter registry.get('db'))

  @newSelect: ->
    select = @db().select @attributes
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
    [results] = select.get.sync select, @tableName
    new @(results[0]) if results[0]

  @byId: (id, cb) ->
    @where(id: id).limit(1).one(cb) if id

  @byIdSync: (id) ->
    @where(id: id).limit(1).oneSync() if id

  @create: (attributes) ->
    new @(attributes)

module.exports = Entity