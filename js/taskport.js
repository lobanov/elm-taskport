(function () {
	"use strict";

  var TaskPort = {
    PROTOCOL: 'elmtaskport:'
  }, _globals;

  _globals = (function(){ return this || (0,eval)("this"); }());

	if (typeof module !== "undefined" && module.exports) {
		module.exports = TaskPort;
	} else if (typeof define === "function" && define.amd) {
		define(function(){return TaskPort;});
	} else {
		_globals.TaskPort = TaskPort;
	}

  TaskPort.install = function() {
    XMLHttpRequest.prototype.__elm_taskport_open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url, async, user, password) {
      console.log("XHR.open", {method, url, async, user, password, TaskPort});
      const m = url.match(/elmtaskport:\/\/([\w]+)/);
      if (m !== null) {
        const functionName = m[1];
        console.log("Function name:", functionName);
        if (functionName in TaskPort && typeof TaskPort[functionName] === 'function') {
          console.log("Found TaskPort function", functionName)
        } else {
          console.error("TaskPort function is not defined", functionName);
        }
        this.__elm_taskport_function = TaskPort[functionName];
      }
      this.__elm_taskport_open(method, url, async, user, password);
    };

    XMLHttpRequest.prototype.__elm_taskport_send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function (body) {    
      Object.defineProperty(this, "responseType", { writable: true });
      Object.defineProperty(this, "response", { writable: true });
      Object.defineProperty(this, "status", { writable: true });

      console.log("XHR.send", {body, xhr: this});
      if (this.__elm_taskport_function) {
        const promise = this.__elm_taskport_function(body);
        promise.then((res) => {
          console.log("Result", res);
          this.responseType = 'json';
          this.response = JSON.stringify(res);
          this.status = 200;
          this.dispatchEvent(new ProgressEvent('load'));
        }).catch((err) => {
          console.error("Error", err);
          this.status = 500;
          this.responseType = 'json';
          this.response = JSON.stringify(err);
          this.dispatchEvent(new ProgressEvent('error'));
        });
      } else {
        this.__elm_taskport_send(body);
      }
    };    
  }
}());
