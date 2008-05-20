{ PowBuild - utilities for automating builds/makes/packages

  Useful for automating and building demos, projects, etc. 
  
  Fpmake and fpcmake are not serving my simple needs. These utilities are born 
  due to my hatred toward GNU Make files (ugliest f*cking cow sh*t ever seen by 
  man).

  Notes: 
    - df is an alias for "default" for quick command line typing
    - ".crap/" directory coined by Lars Olson for .ppu/.a files
    - CleanBeforeRebuild can be set to force

  NOTE: these build utils don't always take advantage of "reusing" compiled
  global PPU files. Other "Make" utilties do. More of this will be implemented 
  in the future. However, I've had "PPU Hell" and "PPU conflicts" when trying 
  to reuse global PPU files (and some projects require regenerating .PAS 
  sources with DEFINES and include file issues. Fpc has bugs too). Compilations 
  may be slower if local ppu copies are generated - but I've rarely found super 
  fast compilations to be that great compared to "CORRECT compilations" that 
  reduce headaches! 
  
  With time... these utils will contain more features.
 
  Authors: L505
           http://z505.com

  License: NRCOL (public domain)
}

unit pwbuildutil; {$mode objfpc} {$H+} {$R+}

interface
uses
  pwtypes,
  pwdirutil,
  arrayfuncs;

type 
  // this may change to more generic "TGroupOptions" or "TCompilerOptions in future if more compilers supported                                             
  TFpcOptions = record
    Name: str15;        // group name
    Dir,                // working directory
    Crapdir,            // subdir for .o/.a/.ppu files (relative to working dir)
    ProgBinFile,        // exe output file name
    ProgBinDir: astr;   // exe output directory
    SmartStrip,         // -XX -CX -Xs
    Compile,
    Rebuild,
    CleanBeforeRebuild,
    IgnoreErr: boo;     // ignore compiler errors
    Extra: astr;                 
    FpcVersion: astr;
    intern: record      // private, not for interface user to worry about
      defines,                                                          
      incpaths, 
      unitpaths: AstrArray;
      craptargetdir: astr;   // i.e. /.crap/i386-win32/
      progtargetdir: astr;   // i.e. /bin/i386-win32/
    end;
  end;


procedure NoteLn(const s: string);
procedure HaltErr(const s: astr);

procedure Init(out opts: TFpcOptions);

function GetProgTargetDir(groupidx: int32): string;

function Compile(const srcunit, opts, fpversion: astr; IgnoreErr: boo): int32;
function Compile(const srcunit: astr; var opts: TFpcOptions): int32;
function Compile(const srcunit, opts, fpversion: astr): int32;
function Compile(const srcunit, opts: astr): int32;

procedure CompileMany(var paths: TPaths; var opts: TFpcOptions; ShowSeparator: boo);
procedure CompileMany(var paths: TPaths; var opts: TFpcOptions);

procedure ShowOpts(var opts: TFpcOptions);

function Build(const srcunit, opts, fpversion: astr; IgnoreErr: boo): int32;
function Build(const srcunit, opts, fpversion: astr): int32;

function RunCmd(const path, comline: astr): int32;
function RunCmd(const path: astr; const comline: array of astr): int32;

procedure AddUnitPath(var opts: TFpcOptions; s: astr);
procedure AddIncPath(var opts: TFpcOptions; s: astr);
procedure AddDefine(var opts: TFpcOptions; s: astr);
procedure AddExtraOpt(var opts: TFpcOptions; s: astr);

procedure ResetUnitPaths(var opts: TFpcOptions);
procedure ResetIncPaths(var opts: TFpcOptions);
procedure ResetDefines(var opts: TFpcOptions);
procedure ResetExtraOpts(var opts: TFpcOptions);

procedure WriteSeparator;
procedure WriteSeparator1;

function Group: str15;
function Rebuilding: boolean;
function DoingAll: boolean;
function Cleaning: boolean;
function doingdefault: boolean;

procedure CreateGroup(paths: TPaths; opts: TFpcOptions);
procedure Run;

procedure SetVisibleGroups(const names: str15array);

(* Todo: 
    -zip (tar, winzip, etc) functions
    -with blacklist of files/directories not needing to be compiled?
    -function to find all .pp/.pas files in a folder and compile all of them
*)

implementation
uses strutils, sysutils, pwfileutil, pwfputil;

type
  TGroup = record
    paths: TPaths;
    opts: TFpcOptions;
  end;

  TGroups = array of TGroup;

var // all build groups 
  Groups: TGroups = nil;
  VisibleGroups: str15array = nil;

function GetProgTargetDir(groupidx: int32): astr;
begin
  result:= '';
  if length(Groups)-1 < groupidx then exit;
  result:= Groups[groupidx].opts.intern.progtargetdir;
end;

procedure SetVisibleGroups(const names: str15array);
begin
  if length(names) > 0 then VisibleGroups:= AssignArray(names);
end;

{ display simple message }
procedure NoteLn(const s: string);
begin writeln('Note: ', s);
end;

{ warn with polite message (no halt) }
procedure WarnLn(const s: string);
begin writeln('Warning: ', s);
end;

{ halt program with polite message }
procedure HaltErr(const s: astr);
begin noteln('quit early: ' + s); halt;
end;

{ overloaded }
procedure HaltErr(s: astr; i: int32);
var tmp: astr = '';
begin str(i, tmp); noteln('quit early: ' + s + tmp); halt;
end;

procedure WriteSeparator;
begin
  writeln('-------------------------------------------------------------------------------');
  writeln('-------------------------------------------------------------------------------');
end;

procedure WriteSeparator1;
begin
  writeln('-------------------------------------------------------------------------------');
end;                

procedure WriteDoneSeparator;
begin 
  writeln('------------FINISHED---------------FINISHED---------------FINISHED-------------');
end;                

{ returns build group }
function Group: str15;
begin
  result:= paramstr(1);
end;

// default groups to compile such as: all, default, df (alias for default)
type eDefGroups = (gDefault,  gDf,  gAll);

// default flags such as clean, rebuild, 
type eDefFlags = (fRebuild,  fClean);

const defgroups: array [eDefgroups] of str15 = ('default', 'df', 'all');
      defflags: array [eDefFlags] of str15 = ('rebuild', 'clean');

function Flag: astr;
begin result:= paramstr(2);
end;

{ checks if we are running a full "rebuild" }
function Rebuilding: boolean;
begin
  result:= false;                          
  if flag = defflags[fRebuild] then result:= true;
end;

{ checks if we are running an "all" build }
function DoingAll: boolean;
begin
  result:= false;
  if group = 'all' then result:= true;   
end;

{ checks if we are running a "clean" }
function Cleaning: boolean;
begin
  result:= false;
  if flag = defflags[fClean] then result:= true;
end;

{ checks if we are running "default" build }
function DoingDefault: boolean;
begin
  result:= false;
  if group = defgroups[gDefault] then result:= true;
  if group = defgroups[gDf] then result:= true;
end;

{ console help }      
procedure ShowHelp;

  procedure IndentedLn(s: string);
  begin writeln('    ', s);
  end;

  procedure ShowLns(a: array of str15);
  var i: int32;
  begin for i:= low(a) to high(a) do IndentedLn(a[i]);
  end;

begin
  writeln('PowBuild by Z505 --> Syntax: build <group> <optional flag>');
  writeln('Type in "build help" to receive extended help information');
  writeln;
  if VisibleGroups = nil then HaltErr('Build author didn''t set visible bulid groups.');
  writeln(' Main Build Groups:');
  ShowLns(Defgroups);
  writeln(' Custom Build Groups:');
  ShowLns(VisibleGroups);
  writeln(' Flags:');
  ShowLns(DefFlags);
  writeln;
  writeln('i.e: build default        (the usual build)');
  writeln('     build df             (df is an alias for "default")');
  writeln('     build df clean       (clean all .ppu/.a files)');
  writeln('     build df rebuild     (builds using -B, also cleans .ppu/.a)');
  writeln('     build all            (compile all build groups, may take long)');
  writeln('     build all clean      (clean .ppu/.a files of all build groups)');
  writeln('     build all rebuild    (cleans all build groups, and builds using -B');
  writeln('     build foobar         (user defined build)');
  writeln('     build foobar clean   (etc. etc. etc.)');
  Halt;
end;

procedure ShowMissingGroupHelp;
begin
  WriteSeparator1;
  writeln('HELP: group (target) you specified was not found in this build system');
  WriteSeparator1;
  Halt;
end;

procedure ShowExtendedHelp;
begin
  writeln('EXTENDED HELP:');
  writeln;
  writeln('  PowBuild is similar to FpMake or Ruby Rake (worse or better!)');
  writeln('  More powerful than GNU make, as build files are true fpc programs');
  writeln('  A "build file" is a fpc program with pwbuildutil in uses clause');
  writeln('  A build file can use any unit in uses (sysutils, pwdirutil, etc.)');
  writeln;
  writeln('  See an example "build.pp" file in any directory.');
  writeln('  Once a build.pp file is found, compile it: "fpc build".');
  writeln('  Then run "build" (help) or "build default" (builds default group)');
  writeln;
  writeln('  A build.pp file must set "visible groups" for the users.');
  writeln('  Build files are "domain specific fpc programs" since they fill a niche');
  writeln;
  writeln('  A "group" is what you may know as a "target" from make files');
  writeln('  To build a specific group, type "build yourgroup"');  
  writeln;
  writeln('...more <enter>');  
  readln;
  WriteSeparator1;
  ShowHelp;
end;

function AllGroupNames: str15array;
var i: int32;
begin
  if length(groups) < 1 then exit;
  setlength(result, length(groups));
  for i:= low(groups) to high(groups) do result[i]:= groups[i].opts.name;
end;

{ ensures targets are setup right }
procedure CheckGroups;
  
  procedure FindGroups;
  var i1: eDefgroups;
      i2: int32;
      found: int32;
  begin
    found:= 0;
    // find default (df), all
    for i1:= low(defgroups) to high(defgroups) do begin
      if group() = defgroups[i1] then inc(found);
    end;
    for i2:= low(groups) to high(groups) do begin
      if groups[i2].opts.name = group() then inc(found);
    end;
    if found < 1 then ShowMissingGroupHelp;
  end;

begin
  if paramcount < 1 then ShowHelp;
  if (paramcount = 1) then if paramstr(1) = 'help' then begin
    ShowExtendedHelp;
    exit;
  end;
   // only find groups in array if any specified at commandline
  if paramcount > 0 then FindGroups;
end;


procedure Run;
var i: int32;
begin
  Checkgroups;
  if length(groups) < 1 then HaltErr('groups array has zero registered');
  for i:= low(groups) to high (groups) do begin
    CompileMany(groups[i].paths, groups[i].Opts);
  end;
end;

{ add a group of files to be compiled with options }
procedure CreateGroup(paths: TPaths; opts: TFpcOptions);
var oldlen: int32;
begin
  if opts.Name = '' then HaltErr('Must specify a name for each group.');
  oldlen:= length(groups);
  setlength(groups, oldlen+1);
  groups[oldlen].paths:= paths;
  groups[oldlen].opts:= opts;
end;


procedure AstrArrayAdd(var a: AstrArray; s: string);
var len: int32;
begin      
  if s = '' then exit;
  len:= length(a);
  setlength(a, len+1);
  a[len]:= s;
end;

procedure AstrArrayReset(var a: AstrArray);
begin
  setlength(a, 0);
end;

{ must call this to ensure Record is initialized }
procedure Init(out opts: TFpcOptions);
begin
  with opts do begin
    SmartStrip:= false; IgnoreErr:= false;  Extra:= ''; CrapDir:= '.crap';  
    ProgBinFile:= ''; ProgBinDir:= ''; Name:= ''; Dir:= '';
    // default version is current compiler of this unit
    FpcVersion:= pwfputil.FpcVersion();
    Rebuild:= rebuilding();
    // if rebuilding or cleaning then CleanBeforeRebuild
    if (Rebuild) or (cleaning) then 
      CleanBeforeRebuild:= true 
    else 
      CleanBeforeRebuild:= false;
    // only compile if we are not cleaning
    Compile:= not cleaning;

    with intern do begin
      setlength(defines, 0);
      setlength(incpaths, 0);
      setlength(unitpaths, 0);
      craptargetdir:= '';
      progtargetdir:= '';
    end;
  end;
end;

{ adds an -Fu path }
procedure AddUnitPath(var opts: TFpcOptions; s: astr);
begin
  AstrArrayAdd(opts.intern.unitpaths, s);
end;

{ adds an -Fi path }
procedure AddIncPath(var opts: TFpcOptions; s: astr);
begin
  AstrArrayAdd(opts.intern.incpaths, s);
end;

{ adds extra compiler option,  i.e. -Sd  -Whatever  -blah }
procedure AddExtraOpt(var opts: TFpcOptions; s: astr);
begin
  opts.extra:= opts.extra + ' ' + s;
end;

{ adds -dSOMEDEFINE }
procedure AddDefine(var opts: TFpcOptions; s: astr);
begin
  AstrArrayAdd(opts.intern.defines, s);
end;

{ ... reset settings in record ...............................................}
procedure ResetExtraOpts(var opts: TFpcOptions);
begin
  opts.extra:= '';
end;

procedure ResetUnitPaths(var opts: TFpcOptions);
begin
  AstrArrayReset(opts.intern.unitpaths);
end;

procedure ResetIncPaths(var opts: TFpcOptions);
begin
  AstrArrayReset(opts.intern.incpaths);
end;

procedure ResetDefines(var opts: TFpcOptions);
begin
  AstrArrayReset(opts.intern.defines);
end;
{ ............................................................................}


{ delete .PPU/.A files a.k.a. "unit crap" }
procedure CleanUnitCrap(const path: astr);
const 
  masks: array [1..5] of string[5] = ('*.ppu', '*.dcu','*.a', '*.res','*.o');
var i, problems: int32;
begin
  problems:= 0;
  noteln('Cleaning: removing files from dir: ' + path);
  for i:= low(masks) to high(masks) do begin
    { warn if deletion of all files unsucessful }
    if not DelFiles(path, masks[i]) then inc(problems);
  end;
  if problems > 0 then WarnLn('did not delete at least 1 file in '+path);
end;

{ makes options Record into a string like '-Fu/path -oProg' }
function MakeOpts(var opts: TFpcOptions): string;
var allopts: astr = '';

  procedure AddSimpleOpts(const opt: astr);
  begin
    allopts:= allopts+' '+opt;
  end;

  procedure AddOpts(const prefix, opt: astr);
  begin
    if length(opt) > 0 then allopts:= allopts+' '+prefix+opt;
  end;

  procedure AddStrArrayOpts;

    procedure Add(prefix: astr; a: AstrArray);
    var i: int32;
    begin
      if length(a) > 0 then
        for i:= low(a) to high(a) do if length(a[i]) > 0 then
          AddOpts(prefix, a[i]);      
    end;

  begin
     Add('-d', opts.intern.defines);
     Add('-Fi', opts.intern.incpaths);
     Add('-Fu', opts.intern.unitpaths);
  end;

  procedure AddTrailSlash(var path: string);
  begin
    path:= IncludeTrailingPathDelimiter(path);
  end;

  procedure AddTrailSlashes;
  begin
    AddTrailSlash(opts.Dir);
    AddTrailSlash(opts.CrapDir);
    AddTrailSlash(opts.ProgBinDir);
  end;

var targdir: string;

begin
  targdir:= '';
  AddTrailSlashes;
  AddStrArrayOpts;                            
  if opts.smartstrip then AddSimpleOpts('-XX -CX -Xs');
  if opts.rebuild then AddSimpleOpts('-B');

  if opts.crapdir <> '' then begin
    targdir:= opts.dir + opts.crapdir + FpcTargetDir();
    if opts.CleanBeforeRebuild then CleanUnitCrap(targdir);
    opts.intern.craptargetdir:= targdir;
    ForceDir(targdir);
  end;

  targdir:= '';                                 
  if opts.progbindir <> '' then begin
    targdir:= opts.dir + opts.progbindir + FpcTargetDir();
    opts.intern.progtargetdir:= targdir;
    if not ForceDir(targdir) then HaltErr('error creating folder: '+targdir); 
  end;

  AddOpts('-FU', opts.intern.craptargetdir);
  AddOpts('-FE', opts.intern.progtargetdir);
  AddOpts('-o', opts.progbinfile);
  AddSimpleOpts(opts.extra);
  result:= allopts;
end;

{ writes Record options to screen as a string }
procedure ShowOpts(var opts: TFpcOptions);
begin
  writeln(makeopts(opts));
end;

{ todo: windows ../units }
function GetFpcUnitBasePath(const fpversion: astr): astr;
begin
  result:= GetEnvironmentVariable('FPCDIR');
{$IFDEF UNIX}
  if result = '' then
  begin
    result:= '/usr/local/lib/fpc/'+fpversion;
    if not DirectoryExists(result) and
       DirectoryExists('/usr/lib/fpc/'+fpversion) 
    then
      result:= '/usr/lib/fpc/'+fpversion;
  end;
{$ENDIF}

end;

{ adds trailing slash if not already there 
  TODO: move function to pwdirutil/strwrap1/pwfileutil/}
procedure ForceTrailSlash(var path: astr);
var len: int32;
begin
  len:= length(path); 
  if len < 1 then exit;
  if path[len] <> SLASH then path:= path + SLASH;
end;

{ retrieve location of fpc path on drive }
procedure GetFpcPath(var fpcpath: astr);
var found: astr;
begin
  if (fpcpath = '') then
  begin
    fpcpath:= 'fpc';
    found:= FileSearch(fpcpath, GetEnvironmentVariable('PATH'));
    if (found <> '') then fpcpath:= found;
  end;
end; 
                     
function GetFpcFullPath: astr;
begin
  {$IFDEF WINDOWS}
    // executeprocess() launches 'fpc' fine on MS Windows
    result:= 'fpc';
  {$ENDIF}
  {$IFDEF UNIX}
    // unix executeprocess() is not as path smart
    GetFpcPath(result);
  {$ENDIF}
end;

{ compile program with options string }
function Compile(const srcunit, opts, fpversion: astr; IgnoreErr: boo): int32;
begin
  result:= ExecuteProcess(GetFpcFullPath(), SrcUnit+' '+opts);
  if (result<>0) and (not IgnoreErr) then
    HaltErr('compiler returned error: ', result);
end;

{ other }
function Compile(const srcunit, opts, fpversion: astr): int32;
begin
  result:= Compile(srcunit, opts, fpversion, false);
end;

{ other }
function Compile(const srcunit, opts: astr): int32;
begin
  result:= Compile(srcunit, opts, FpcVersion(), false);
end;

{ compile program with options in a record }
function Compile(const srcunit: astr; var opts: TFpcOptions): int32;
var madeopts: astr;
    path: astr;
begin
  madeopts:= makeopts(opts);
  if not opts.Compile then exit; // just clean or do other tasks
  path:= opts.dir+srcunit;
  writeln('>>> COMPILING: ', path);
  result:= Compile(path, madeopts, opts.FpcVersion, opts.IgnoreErr);
end;

procedure CompileMany(var paths: TPaths; var opts: TFpcOptions; ShowSeparator: boo);
var i: int32;
begin
  if paths.count < 1 then exit;
  WriteSeparator1;
  writeln('----- PROCESSING GROUP: ', opts.Name, ' -----');
  WriteSeparator1;
  for i:= low(paths.items) to high(paths.items) do begin
    opts.dir:= paths.items[i].path;
    Compile(paths.items[i].fname, opts);
    if ShowSeparator then WriteSeparator1; // shows ----------- lines
  end;
  WriteDoneSeparator; // finishing separator :o)
end;

procedure CompileMany(var paths: TPaths; var opts: TFpcOptions);
begin
  CompileMany(paths, opts, true);
end;

{ same as compile but forces fpc build -B }
function Build(const srcunit, opts, fpversion: astr; IgnoreErr: boo): int32;
begin
  result:= Compile(srcunit, '-B ' + opts, fpversion, IgnoreErr);
end;

{ default }
function Build(const srcunit, opts, fpversion: astr): int32;
begin
  result:= Build(srcunit, opts, fpversion, false);
end;

{ simple way to run a command }
function RunCmd(const path, comline: astr): int32;
begin
  result:= ExecuteProcess(path, comline);
end;

{ overloaded with array }
function RunCmd(const path: string; const comline: array of astr): int32;
begin
  result:= ExecuteProcess(path, comline);
end;

end.

(*
function compile(const srcunit: astr; const opts: TFpcOptions): int32;
var allopts: astr = '';

  procedure AddOpts(const opts: astr);
  begin
    allopts:= allopts+' '+opts;
  end;

  procedure AddStrArrayOpts;

    procedure Add(prefix: astr; arr: AstrArray);
    var i: longword;
    begin
    if length(arr) > 0 then
      for i:= low(arr) to high(arr) do 
        AddOpts(prefix + arr[i]);      
    end;

  begin
     Add('-d', opts.defines);
     Add('-Fi', opts.incpaths);
     Add('-Fu', opts.unitpaths);
  end;

begin
  if not opts.intern.inited then halterr('"opts" record must be inited before using');
  AddStrArrayOpts;
  if opts.smartstrip then AddOpts('-XX -CX -Xs');
  if opts.build then AddOpts('-B');
  AddOpts('-FU'+opts.OutCrapPath);
  AddOpts('-o'+opts.outprog);
  AddOpts(opts.extra);
  result:= compile('fpc', srcunit+' '+allopts);
end;


procedure CheckIfOptsInited(const opts: TFpcOptions);
begin
  if not opts.intern.inited then 
    HaltErr('"opts" record must be inited before using');
end;
*)
