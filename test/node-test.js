const TaskPort = require('./build/taskport.min.js');
const TaskPortFixture = require('./fixture.js');
const { XMLHttpRequest } = require('xmlhttprequest');
const { Elm } = require('./build/elm.js');

global.XMLHttpRequest = function() {
  XMLHttpRequest.call(this);
  TaskPort.install({ logInteropErrors: false, logCallErrors: false }, this);
}

TaskPortFixture.register(TaskPort);

const app = Elm.Main.init({ flags: "" });
const failedTestDetails = {};
const counts = { pass: 0, fail: 0, total: 0 };

app.ports.reportTestResult.subscribe(function ({testId, pass, details}) {
  counts.total++;
  if (pass) {
    counts.pass++;
  } else {
    failedTestDetails[testId] = details;
    counts.fail++;
  }
});

app.ports.completed.subscribe(function () {
  // ensure all test reports are in
  setTimeout(() => {
    if (counts.total == 0) {
      console.error("No tests were executed");
      process.exit(1);
    } else if (counts.fail > 0) {
      console.error(`Executed ${counts.total} test cases, of which ${counts.fail} have failed`);
      Object.entries(failedTestDetails).forEach(([testId, details]) => { console.error("Failed test: " + testId + "\n" + details); });
      process.exit(1);
    } else {
      console.error(`Executed ${counts.total} test cases`);
    }
  }, 100);
})

app.ports.start.send("Go");
