# Description:
#   Persist hubot's brain to Google Cloud Datastore
#
# Configuration:
#   DATASTORE_KIND
#   GCLOUD_PROJECT or GAE_LONG_APP_ID
#   MEMCACHE_ADDR
#   MEMCACHE_PORT
#
# Commands:
#   None

gcloud = require 'gcloud'

Memcached = require 'memcached'
memcachedAddr = process.env.MEMCACHE_ADDR or
  process.env.MEMCACHE_PORT_11211_TCP_ADDR or
  'localhost'
memcachedPort = process.env.MEMCACHE_PORT or
  process.env.MEMCACHE_PORT_11211_TCP_PORT or
  '11211'

memcached = new Memcached("#{memcachedAddr}:#{memcachedPort}", {
  timeout: 1000
  retries: 0
  failures: 0
  remove: true
})

wrap = (data)->
  return data if typeof(data) is 'object'
  _value: data

unwrap = (data)->
  return data['_value'] if data['_value']
  data

jsonEqual = (a, b)->
  JSON.stringify(a) is JSON.stringify(b)

prefix = "hubot_brain_"

cache =
  get: (keys, callback)->
    _get = ->
      new Promise (resolve, reject)->
        entitys = []
        for key in keys
          continue unless key
          entitys.push key
        _keys = for key in entitys then prefix + key.name
        memcached.getMulti _keys, (err, reslut)->
          return callback err if err
          _reslut = for key in entitys
            name = prefix + key.name
            data = reslut[name]
            if data then {key: key, data: data} else null
          callback null, _reslut
    _get()
    .then callback, callback

  save: (entitys, callback)->
    life = 10 * 60 # 10 minutes
    save = (key, data)->
      new Promise (resolve, reject)->
        memcached.set key, data, life, (err)->
          return reject err if err
          resolve null
    tasks = for entity in entitys
      save prefix + entity.key.name, entity.data
    Promise.all(tasks)
    .then (err)->
      callback err[0]
    .catch callback

module.exports = (robot)->
  KIND = process.env.DATASTORE_KIND or "hubot"
  projectId = process.env.GCLOUD_PROJECT or process.env.GAE_LONG_APP_ID
  datastore = gcloud
    projectId: projectId
  .datastore()

  robot.brain.setAutoSave false

  getData = ->
    query = datastore.createQuery KIND
    datastore.runQuery query, (err, entitys)->
      return  robot.logger.error err if err
      cache.save entitys, (err)->
        robot.logger.debug err if err
        _private = {}
        for entity in entitys
          _private[entity.key.name] = unwrap(entity.data)
        robot.brain.mergeData {_private: _private}
        robot.brain.resetSaveInterval 10
        robot.brain.setAutoSave true
  
  robot.brain.on 'save', (data = {}) ->
    entitys = for k,v of data._private
      key = datastore.key [KIND, k]
      {key: key, data: wrap(v)}
    keys = for entity in entitys then entity.key
    cache.get keys, (err, reslut)->
      return robot.logger.error if err
      _entitys = []
      for res, i in reslut
        entity = entitys[i]
        unless res
          _entitys.push entity
          continue
        unless jsonEqual res.data, entity.data
          _entitys.push entity
          continue
      unless _entitys.length > 0
        robot.logger.debug "datastore-brain", "skip save"
        return
      datastore.save _entitys, (err, res) ->
        return robot.logger.error err if err
        cache.save entitys, (err) ->
          robot.logger.debug "datastore-brain", err if err

  getData()

  return

