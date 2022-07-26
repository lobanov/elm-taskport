import { Namespace } from './namespace.js';

describe("Namespace", () => {
  it('should be initialized empty with a given version', () => {
    const ns = new Namespace('1.2.3');
    expect(ns.version).toStrictEqual('1.2.3');
    expect(ns.names()).toStrictEqual([]);
  });

  it('should throw if created with a non-string version', () => {
    expect(() => new Namespace(null)).toThrow();
    expect(() => new Namespace(undefined)).toThrow();
    expect(() => new Namespace([])).toThrow();
  });

  it('should throw if created with an invalid version string', () => {
    expect(() => new Namespace('()')).toThrow();
  });

  it('should be possible to find a registered function', () => {
    const ns = new Namespace('1.2.3');
    ns.register('functionName', () => 'result');
    expect(ns.names()).toEqual(expect.arrayContaining(['functionName']));
    expect(ns.find('functionName')).not.toBeUndefined();
    expect(ns.find('functionName')()).toStrictEqual('result');
  });

  it('should throw if registering a function with an invalid name', () => {
    const ns = new Namespace('1.2.3');
    expect(() => ns.register('invalid-name', () => {})).toThrow();
  });
});
