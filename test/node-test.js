const TaskPort = require('../js/taskport.js');
const XMLHttpRequest = require('xmlhttprequest');

TaskPort.install(XMLHttpRequest.prototype);

const app = require('./build/elm.cjs').Main.init({ flags: "" });

app.ports.reportTestResult.subscribe(function (result) {
    console.log(result);
});

app.ports.start.send("");
