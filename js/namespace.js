
export function Namespace(version) {
  // TODO validate input
  this.version = version;
  this.functions = {};

  this.register = function(name, fn) {
    if (!name.match(/^\w+$/)) {
      throw new Error("Invalid function name: " + name);
    }
    if (name in this.functions) {
      throw new Error(name + " is already used");
    }
    this.functions[name] = fn;
  }

  /**
   * @returns {string[]} names of all registered functions
   */
  this.names = function() {
    return Object.keys(this.functions);
  }

  /**
   * 
   * @param {string} name function name for the lookup
   * @returns {(any): any | undefined} function with the given name if found
   */
  this.find = function(name) {
    if (name in this.functions) {
      return this.functions[name];
    }
  }
}
