const MODULE_VERSION = "1.0.2";

const functions = {};

/** Returns a promise regardless of the return value of the fn */
function callAndReturnPromise(fn, args) {
  try {
    return Promise.resolve(fn(args));
  } catch (e) {
    return Promise.reject(e);
  }
}

/** Configure JavaScript environment on the current page to enable interop calls. */
function install(xhrProto) {
  if (xhrProto === undefined) {
    xhrProto = XMLHttpRequest.prototype;
  }
  xhrProto.__elm_taskport_open = xhrProto.open;
  xhrProto.open = function (method, url, async, user, password) {
    const m = url.match(/elmtaskport:\/\/([\w]+)\?v=(\d\.\d\.\d)/);
    if (m !== null) {
      const functionName = m[1];
      const moduleVersion = m[2];
      this.__elm_taskport_version = moduleVersion;
      this.__elm_taskport_function_call = true;
      if (functionName in functions && typeof functions[functionName] === 'function') {
        this.__elm_taskport_function = functions[functionName];
      } else {
        console.error("TaskPort function is not registered", functionName);
      }
    }
    this.__elm_taskport_open(method, url, async, user, password);
  };

  xhrProto.__elm_taskport_send = xhrProto.send;
  xhrProto.send = function (body) {
    Object.defineProperty(this, "responseType", { writable: true });
    Object.defineProperty(this, "response", { writable: true });
    Object.defineProperty(this, "status", { writable: true });

    if (this.__elm_taskport_function_call) {
      if (this.__elm_taskport_version !== MODULE_VERSION) {
        console.error("TaskPort version conflict. Elm-side is " + this.__elm_taskport_version
          + ", but JavaScript-side is " + MODULE_VERSION + ". Don't forget that both sides must use the same version");

        this.status = 400;
        this.dispatchEvent('error');
      } else if (this.__elm_taskport_function === undefined) {
        this.status = 404;
        this.dispatchEvent('error');
      }

      const parsedBody = JSON.parse(body);
      const promise = callAndReturnPromise(this.__elm_taskport_function, parsedBody);
      promise.then((res) => {
        this.responseType = 'json';
        this.response = (res === undefined)? 'null' : JSON.stringify(res); // force null if the function does not return a value
        this.status = 200;
        this.dispatchEvent('load');
      }).catch((err) => {
        this.status = 500;
        this.responseType = 'json';
        this.response = JSON.stringify(err);
        this.dispatchEvent('error');
      });
    } else {
      this.__elm_taskport_send(body);
    }
  };    
}

/** Register given JavaScript function under a particular name and make it available for the interop. */
function register(name, fn) {
  if (!name.match(/^\w+$/)) {
    throw new Error("Invalid function name: " + name);
  }
  if (name in functions) {
    throw new Error(name + " is already used");
  }
  functions[name] = fn;
}


(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
      // AMD. Register as an anonymous module.
      define([], factory);
  } else if (typeof module === 'object' && module.exports) {
      // Node. Does not work with strict CommonJS, but
      // only CommonJS-like environments that support module.exports,
      // like Node.
      module.exports = factory();
  } else {
      // Browser globals (root is window)
      root.returnExports = factory();
}
}(typeof self !== 'undefined' ? self : this, function () {

  return {
    install,
    register
  };
}));
