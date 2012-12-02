import httpclient, parseopt, os, strutils, osproc

import packageinfo

type
  TActionType = enum
    ActionNil, ActionUpdate, ActionInstall

  TAction = object
    case typ: TActionType
    of ActionNil: nil
    of ActionUpdate:
      optionalURL: string # Overrides default package list.
    of ActionInstall:
      optionalName: seq[string] # When this is @[], installs package from current dir.

const
  help = """
Usage: babel COMMAND

Commands:
  install        Installs a list of packages.
  update         Updates package list. A package list URL can be optionally specificed.
"""
  babelVersion = "0.1.0"
  defaultPackageURL = "https://github.com/nimrod-code/packages/raw/master/packages.json"

proc writeHelp() =
  echo(help)
  quit(QuitSuccess)

proc writeVersion() =
  echo(babelVersion)
  quit(QuitSuccess)

proc parseCmdLine(): TAction =
  result.typ = ActionNil
  for kind, key, val in getOpt():
    case kind
    of cmdArgument:
      if result.typ == ActionNil:
        case key
        of "install":
          result.typ = ActionInstall
          result.optionalName = @[]
        of "update":
          result.typ = ActionUpdate
          result.optionalURL = ""
        else: writeHelp()
      else:
        case result.typ
        of ActionNil:
          assert false
        of ActionInstall:
          result.optionalName.add(key)
        of ActionUpdate:
          result.optionalURL = key
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": writeHelp()
      of "version", "v": writeVersion()
    of cmdEnd: assert(false) # cannot happen
  if result.typ == ActionNil:
    writeHelp()

proc update(url: string = defaultPackageURL) =
  echo("Downloading package list from " & url)
  downloadFile(url, getHomeDir() / ".babel" / "packages.json")
  echo("Done.")

proc findBabelFile(dir: string): string =
  for kind, path in walkDir(dir):
    if kind == pcFile and path.splitFile.ext == ".babel":
      return path
  return ""

proc copyFileD(fro, to: string) =
  echo(fro, " -> ", to)
  copyFile(fro, to)

proc getBabelDir: string = return getHomeDir() / ".babel"

proc getLibsDir: string = return getBabelDir() / "libs"

proc samePaths(p1, p2: string): bool =
  ## Normalizes path (by adding a trailing slash) and compares.
  let cp1 = if not p1.endsWith("/"): p1 & "/" else: p1
  let cp2 = if not p2.endsWith("/"): p2 & "/" else: p2
  return cmpPaths(cp1, cp2) == 0

proc changeRoot(origRoot, newRoot, path: string): string =
  ## origRoot: /home/dom/
  ## newRoot:  /home/test/
  ## path:     /home/dom/bar/blah/2/foo.txt
  ## Return value -> /home/test/bar/blah/2/foo.txt
  if path.startsWith(origRoot):
    return newRoot / path[origRoot.len .. -1]
  else:
    raise newException(EInvalidValue,
      "Cannot change root of path: Path does not begin with original root.")

proc copyFilesRec(origDir, currentDir: string, pkgInfo: TPackageInfo) =
  for kind, file in walkDir(currentDir):
    if kind == pcDir:
      var skip = false
      for ignoreDir in pkgInfo.skipDirs:
        if samePaths(file, origDir / ignoreDir):
          skip = true
          break
      let thisDir = splitPath(file).tail 
      assert thisDir != ""
      if thisDir[0] == '.': skip = true
      if thisDir == "nimcache": skip = true
      
      if skip: continue
      # Create the dir.
      createDir(changeRoot(origDir, getLibsDir() / pkgInfo.name, file))
      
      copyFilesRec(origDir, file, pkgInfo)
    else:
      var skip = false
      if file.splitFile().name[0] == '.': skip = true
      if file.splitFile().ext == "": skip = true
      for ignoreFile in pkgInfo.skipFiles:
        if samePaths(file, origDir / ignoreFile):
          skip = true
          break
      
      if not skip:
        copyFileD(file, changeRoot(origDir, getLibsDir() / pkgInfo.name, file)) 
      
proc installFromDir(dir: string) =
  let babelFile = findBabelFile(dir)
  if babelFile == "":
    quit("Specified directory does not contain a .babel file.", QuitFailure)
  var pkgInfo = readPackageInfo(babelFile)
  if not existsDir(getLibsDir() / pkgInfo.name):
    createDir(getLibsDir() / pkgInfo.name)
  else: echo("Warning: Package already exists.")
  
  # Find main project file.
  let nimFile = dir / pkgInfo.name.addFileExt("nim")
  let nimrodFile = dir / pkgInfo.name.addFileExt("nimrod")
  if existsFile(nimFile) or existsFile(nimrodFile):
    if existsFile(nimFile):
      copyFileD(nimFile, changeRoot(dir, getLibsDir(), nimFile))
      pkgInfo.skipFiles.add(changeRoot(dir, "", nimFile))
    elif existsFile(nimrodFile):
      copyFileD(nimrodFile, changeRoot(dir, getLibsDir(), nimrodFile))
      pkgInfo.skipFiles.add(changeRoot(dir, "", nimrodFile))
  else:
    quit("Could not find main package file.", QuitFailure)
  
  copyFilesRec(dir, dir, pkgInfo)

proc install(packages: seq[String]) =
  if packages == @[]:
    installFromDir(getCurrentDir())
  else:
    if not existsFile(getBabelDir() / "packages.json"):
      quit("Please run babel update.", QuitFailure)
    for p in packages:
      var pkg: TPackage
      if getPackage(p, getBabelDir() / "packages.json", pkg):
        let downloadDir = (getTempDir() / "babel" / pkg.name)
        case pkg.downloadMethod
        of "git":
          echo("Executing git...")
          removeDir(downloadDir)
          let exitCode = execCmd("git clone " & pkg.url & " " & downloadDir)
          if exitCode != QuitSuccess:
            quit("Execution of git failed.", QuitFailure)
        else: quit("Unknown download method: " & pkg.downloadMethod, QuitFailure)
        installFromDir(downloadDir)
      else:
        quit("Package not found.", QuitFailure)

proc doAction(action: TAction) =
  case action.typ
  of ActionUpdate:
    if action.optionalURL != "":
      update(action.optionalURL)
    else:
      update()
  of ActionInstall:
    install(action.optionalName)
  of ActionNil:
    assert false

when isMainModule:
  if not existsDir(getHomeDir() / ".babel"):
    createDir(getHomeDir() / ".babel")
  if not existsDir(getHomeDir() / ".babel" / "libs"):
    createDir(getHomeDir() / ".babel" / "libs")
  
  parseCmdLine().doAction()
  
  
  
  
  