# How to publish a new version

## Compile and test everything

Build and test automatically in Node.

```sh
yarn node-test
```

Build test website and check manually in browsers.

```sh
yarn web-test
```

Should check at least:
* Chrome
* Firefox
* Safari

## Determine new version number for Elm package

Elm enforces strict rules for incrementing version numbers for packaging, so need to ask Elm for what the next version number to be like by running `elm bump`.

```sh
elm bump
```

The command will update `elm.json` file with the new version number depending on the nature of the changes made.

## Update version number in the code

The following files need to be updated with the new Elm package version in `elm.json` file:
* `package.json`
* `src/TaskPort.elm` (see `moduleVersion`)
* `js/taskport.js` (see `MODULE_VERSION`)

## Release Elm package

* Check-in everything to the repo
* Tag code in the `main` branch with the updated version number:

```sh
git tag <version>
```

* Push the tag to the repo

```sh
git push --tags
```

* Publish Elm package

```sh
elm publish
```

## Release NPM package

```sh
yarn publish
```
