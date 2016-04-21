# Description:
#   Persist hubot's brain to Google Cloud Datastore
#
# Configuration:
#   DATASTORE_KIND
#   GCLOUD_PROJECT or GAE_LONG_APP_ID
#
# Commands:
#   None

gcloud = require 'gcloud'

wrap = (data)->
  return data if typeof(data) is 'object'
  _value: data

unwrap = (data)->
  return data['_value'] if data['_value']
  data

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
      _private = {}
      for entity in entitys
        _private[entity.key.name] = unwrap(entity.data)
      robot.brain.mergeData {_private: _private}
      robot.brain.resetSaveInterval 10
      robot.brain.setAutoSave true
  
  robot.brain.on 'save', (data = {}) ->
    entitys = for k,v of data._private
      robot.logger.debug "save \"#{k}\" into datastore-brain"
      key = datastore.key [KIND, k]
      {key: key, data: wrap(v)}
    datastore.save entitys, (err, res) ->
      robot.logger.error err if err

  getData()

  return

