export const URL_PREFIX = "elmtaskport://"

/**
 * Parses given url string and extracts information useful for TaskPort interop.
 * for the default namespace: elmtaskport:///functionName?v=MAJOR.MINOR.PATCH
 * for a specific namespace: elmtaskport://author-name/package-name/functionName?v=MAJOR.MINOR.PATCH&nsv=NAMESPACE_VERSION
 * 
 * @param {string} url an url as a string
 * @return {{apiVersion: string, functionName: string, namespaceName: string, namespaceVersion: string} | undefined}
 * components of the URL or undefined if could not parse
 */
export function parseUrl(url) {
  const m = url.match(/^elmtaskport:\/\/([\w-]+\/[\w-]+)?\/([\w]+)\?v=(\d\.\d\.\d)(?:&nsv=([\w.-]+))?$/);
  if (!m) {
    return;
  }

  const [_, namespaceName, functionName, apiVersion, namespaceVersion] = m;
  if (namespaceName !== undefined && namespaceVersion === undefined) {
    return;
  }
  return { namespaceName, namespaceVersion, apiVersion, functionName };
}
