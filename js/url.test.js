import { parseUrl } from './url.js';

describe("parseUrl", () => {
  it('should fail with v1.2-style URL', () => {
    expect(parseUrl('elmtaskport://functionName?v=1.2.0')).toBeUndefined();
  });

  it('should parse URLs with functions the default namespace', () => {
    expect(parseUrl('elmtaskport:///functionName?v=2.0.0'))
      .toMatchObject({namespaceName: undefined, namespaceVersion: undefined, functionName: 'functionName', apiVersion: '2.0.0'});
  });

  it('should parse URLs with functions in a namespace', () => {
    expect(parseUrl('elmtaskport://auth0r-name/pac4age-name/functionName?v=2.0.0&nsv=123'))
      .toMatchObject({namespaceName: 'auth0r-name/pac4age-name', namespaceVersion: '123', functionName: 'functionName', apiVersion: '2.0.0'});
  });

  it('should fail if using a namespace without namespace version', () => {
    expect(parseUrl('elmtaskport://auth0r-name/pac4age-name/functionName?v=2.0.0')).toBeUndefined();
  });
});
