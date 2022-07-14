const TaskPort = require('../js/taskport.js');
const { XMLHttpRequest } = require('xmlhttprequest');
const { Elm } = require('./build/elm.js');

global.XMLHttpRequest = function() {
    XMLHttpRequest.call(this);
    TaskPort.install(this);
}

TaskPort.register("noArgs", function() {
  return "string value";
});

TaskPort.register("noArgs2", function() {
    return [ 'value1', 'value2' ];
});

TaskPort.register("noArgs3", function() {
    return { key1: 'value1', key2: 'value2' }
});

const app = Elm.Main.init({ flags: "" });

app.ports.reportTestResult.subscribe(function (result) {
    console.log(result);
});

app.ports.start.send("");
