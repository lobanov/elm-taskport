const TaskPort = require('../js/taskport.js');
const TaskPortFixture = require('./fixture.js');
const { XMLHttpRequest } = require('xmlhttprequest');
const { Elm } = require('./build/elm.js');

global.XMLHttpRequest = function() {
    XMLHttpRequest.call(this);
    TaskPort.install(this);
}

TaskPortFixture.register(TaskPort);

const app = Elm.Main.init({ flags: "" });

app.ports.reportTestResult.subscribe(function (result) {
    console.log(result);
});

app.ports.start.send("");
