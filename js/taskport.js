const TaskPort = {
  MODULE_VERSION: "1.0.2"
}

/** Returns a promise regardless of the return value of the fn */
function callAndReturnPromise(fn, args) {
  try {
    return Promise.resolve(fn(args));
  } catch (e) {
    return Promise.reject(e);
  }
}

/** Configure JavaScript environment on the current page to enable interop calls. */
TaskPort.install = function() {
  XMLHttpRequest.prototype.__elm_taskport_open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, async, user, password) {
    const m = url.match(/elmtaskport:\/\/([\w]+)\?v=(\d\.\d\.\d)/);
    if (m !== null) {
      const functionName = m[1];
      const moduleVersion = m[2];
      this.__elm_taskport_version = moduleVersion;
      this.__elm_taskport_function_call = true;
      if (functionName in TaskPort && typeof TaskPort[functionName] === 'function') {
        this.__elm_taskport_function = TaskPort[functionName];
      } else {
        console.error("TaskPort function is not registered", functionName);
      }
    }
    this.__elm_taskport_open(method, url, async, user, password);
  };

  XMLHttpRequest.prototype.__elm_taskport_send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function (body) {
    Object.defineProperty(this, "responseType", { writable: true });
    Object.defineProperty(this, "response", { writable: true });
    Object.defineProperty(this, "status", { writable: true });

    if (this.__elm_taskport_function_call) {
      if (this.__elm_taskport_version !== TaskPort.MODULE_VERSION) {
        console.error("TaskPort version conflict. Elm-side is " + this.__elm_taskport_version
          + ", but JavaScript-side is " + TaskPort.MODULE_VERSION + ". Don't forget that both sides must use the same version");

        this.status = 400;
        this.dispatchEvent(new ProgressEvent('error'));
      } else if (this.__elm_taskport_function === undefined) {
        this.status = 404;
        this.dispatchEvent(new ProgressEvent('error'));
      }

      const parsedBody = JSON.parse(body);
      const promise = callAndReturnPromise(this.__elm_taskport_function, parsedBody);
      promise.then((res) => {
        this.responseType = 'json';
        this.response = (res === undefined)? 'null' : JSON.stringify(res); // force null if the function does not return a value
        this.status = 200;
        this.dispatchEvent(new ProgressEvent('load'));
      }).catch((err) => {
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

/** Register given JavaScript function under a particular name and make it available for the interop. */
TaskPort.register = function (name, fn) {
  if (!name.match(/^\w+$/)) {
    throw new Error("Invalid function name: " + name);
  }
  if (name in TaskPort) {
    throw new Error(name + " is already used");
  }
  TaskPort[name] = fn;
}

export default TaskPort;
