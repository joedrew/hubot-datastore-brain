/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS205: Consider reworking code to avoid use of IIFEs
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
// Description:
//   Persist hubot's brain to Google Cloud Datastore
//
// Configuration:
//   DATASTORE_KIND
//   GCLOUD_PROJECT or GAE_LONG_APP_ID
//
// Commands:
//   None

const { Datastore } = require('@google-cloud/datastore');

const wrap = function(data){
  return {value: data};
};

const unwrap = function(data){
  if (data['value']) { return data['value']; }
  return data;
};

const jsonEqual = (a, b)=> JSON.stringify(a) === JSON.stringify(b);

const prefix = "hubot_brain_";

module.exports = function(robot){
  const KIND = process.env.DATASTORE_KIND || "hubot";
  const projectId = process.env.GCLOUD_PROJECT || process.env.GAE_LONG_APP_ID;
  const datastore = new Datastore({
    projectId: projectId
  });
  robot.brain.setAutoSave(false);

  const getData = function() {
    const query = datastore.createQuery(KIND);
    return datastore.runQuery(query, function(err, entitys) {
      if (err) { return  robot.logger.error(err); }

      const _private = {};
      for (let entity of Array.from(entitys)) {
        _private[entity.key.name] = unwrap(entity.data);
      }
      robot.brain.mergeData({_private});
      robot.brain.resetSaveInterval(10);
      return robot.brain.setAutoSave(true);
    });
  };

  robot.brain.on('save', function(data) {
    let key, entity;
    if (data == null) { data = {}; }
    robot.logger.error("saving data", data);
    const entities = (() => {
      const result = [];
      for (let k in data._private) {
        const v = data._private[k];
        key = datastore.key([KIND, k]);
        robot.logger.error("key", key);
        robot.logger.error("key path", key.path);
        result.push({key, data: wrap(v)});
      }
      return result;
    })();
    robot.logger.error("entities", entities);
    return datastore.save(entities, function(err, res) {
      if (err) { return robot.logger.error(err); }
    });
  });

  getData();

};

