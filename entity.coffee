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

  @idAttribute: 'id'
  @statusAttribute: 'is_deleted'

  constructor: (attributes) ->
    @constructor.preprocessClassVariables()
    attributes = {} if not _.isObject(attributes) or _.isArray(attributes)
    @attributes = @filterAttributes attributes

    defaults = @constructor.defaults
    if _.isObject defaults
      for own attrName, attrValue of defaults
        @attributes[attrName] = attrValue if isFalsy @attributes[attrName]

    @id = @attributes.id
    delete @attributes.id

  tableName: ->
    @constructor.tableName

  db: -> @constructor.db()

  isSaved: -> !!@id

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

  changes: ->
    _.clone @__changes if @isDirty()

  serialize: ->
    _.extend id: @id, @attributes

  querySerialize: () ->
    @querySerializeFinale @filterAttributes(@attributes)

  querySerializeChanges: ->
    @querySerializeFinale(@filterAttributes(@__changes)) if @isDirty()

  querySerializeFinale: (result) ->
    delete result.id
    statusAttr = @constructor.statusAttribute
    isDeleted = @attributes[statusAttr]
    isDeleted = no if isFalsy isDeleted
    result[statusAttr] = isDeleted
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
    @set @constructor.statusAttribute, yes
    @save cb

  removeSync: ->
    @set @constructor.statusAttribute, yes
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
    @db().where(id: @id).update.sync @db(), tbl, @querySerializeChanges()

  @db: ->
    db || (db = new Db.Adapter registry.get('db'))

  @preprocessClassVariables: ->
    return if @__preprocessed
    @attributes = @attributes.split(@rAttributeDelimiter) if _.isString @attributes
    @attributes.push @statusAttribute unless @statusAttribute in @attributes
    @__preprocessed = yes

  @newSelect: ->
    select = @db().select ['id'].concat(@attributes)
    select.where @constructor.statusAttribute + ' = 0'
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

  @byIdSync: (id) ->
    @where(id: id).limit(1).oneSync() if id

  @create: (attributes) ->
    new @(attributes)

module.exports = Entity