const script = require('./build/elm.js');

const app = script.Elm.Main.init({ flags: "" });
app.ports.reportTestResult.subscribe(function (result) {
    console.log(result);
});

app.ports.start.send("");
