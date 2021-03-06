(*
    Copyright © 2011, 2012 MLstate

    This file is part of Opa.

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*)

(* ------------------------------------------------------------ *)
(* Tags, flags, directory contexts and custom stuff             *)
(* ------------------------------------------------------------ *)

(* -- Directory contexts -- *)

shared_namespace_dir "compiler/libqmlcompil";
include_subdirs "compiler/qmlflat";
shared_namespace_dir "compiler/opa";
include_subdirs "compiler/opalib";
shared_namespace_dir "compiler/opalang";
shared_namespace_dir "ocamllib/appruntime";
shared_namespace_dir "ocamllib/libnet";
shared_namespace_dir "ocamllib/database";

(* -- Stubs -- *)

def_stubs ~dir:"ocamllib/libbase" "stubs";
def_stubs ~dir:"ocamllib/libsecurity" "ssl_ext";
def_stubs ~dir:"ocamllib/appruntime" "io";

(* PATHS *)

let plugins_dir = "lib" / "plugins" in
let libbase_dir = "ocamllib" / "libbase" in
let opa_prefix = Pathname.pwd / !Options.build_dir in

let extralib_opt = function
  | Some (lib,ldir,idir) ->
      flag ["link"; "use_"^lib] (S [A "-ccopt"; P ("-L" ^ ldir); A"-cclib"; A ("-l" ^ lib)]);
      flag ["compile"; "c"; "use_"^lib] (S [A"-I"; P idir])
  | None -> ()
in
extralib_opt Config.libnatpmp;
extralib_opt Config.miniupnpc;

(* Pre-installed system libs *)
let linux_system_libs = ["iconv"]
and mac_system_libs = []
and windows_system_libs = []
in

let system_libs =
  if is_linux || is_fbsd then linux_system_libs
  else if is_mac then mac_system_libs
  else if is_win then windows_system_libs
  else []
in

let is_system_libs lib = List.mem lib system_libs in

let filter_system_libs l =
  List.filter (fun x -> not (is_system_libs x)) l
in

begin match Config.camlidl with
| None -> ()
| Some camlidl ->
    flag ["link"; "use_camlidl"] (S [A "-cclib"; P "-lcamlidl" ]);

    rule "camlidl processing: .idl -> .ml .mli _stubs.c lib_stubs.clib"
      ~deps:[ "%(dir)stubs%(name).idl" ]
      ~prods:[ "%(dir:<**/>)stubs%(name:<*> and not <*.*> and not <>).mli";
               "%(dir:<**/>)stubs%(name:<*> and not <*.*> and not <>).ml" ;
               "%(dir:<**/>)stubs%(name:<*> and not <*.*> and not <>)_stubs.c" ]
      ~insert:`top
      (fun env _build ->
         let dir = env "%(dir)" in
         let name = env "%(name)" in

         def_stubs ~dir (name ^ "_idl");

         Cmd(S[Sh"cd"; P dir; Sh"&&";
               P camlidl; A"-prepro"; P"/usr/bin/cpp"; A"-no-include"; P ("stubs" ^ name -.- "idl") ])
      )
end;

(* -- Ocamldoc plugin -- *)

flag_and_dep ["ocaml"; "doc"] (S[A"-g";P"tools/utils/ocamldoc_plugin.cmxs"]);


(* ------------------------------------------------------------ *)
(* Additional rules: internal                                   *)
(* ------------------------------------------------------------ *)

(* -- static ppdebug -- *)
(* what happens here is:
 * - generate the file _build/environment containing the environment vars used by ppdebug
 * - make files tagged with with_static_proprecessing depend on _build/environment
 * - tag any ml file containing some static ppdebug with the tag with_static_proprecessing
 *)

let static_ppdebug_vars = [
  "CPS_WITH_ML_CLOSURE"; (* disable the use of qml closures in cps continuations
                          * (for performance reasons) *)
  "CPS_STACK_SIZE" ; (* observe the size of the stack @ cps return *)
] in
let environment = "environment" in
let build_env_strings =
    (List.map
       (fun s ->
          Printf.sprintf "let %s = %s\n"
            s (try Printf.sprintf "Some %S" (Sys.getenv s)
               with Not_found -> "None")
       ) static_ppdebug_vars) in
dep ["with_static_preprocessing"] [environment];

rule "environment generation"
  ~prods:[environment;"i_dont_exist"](* fake prod to make sure this rule is
                                      * always called *)
  (fun env build ->
     Echo (build_env_strings, environment));

let generate_ocamldep_rule ml_or_mli =
  rule ("ocaml dependencies " ^ ml_or_mli ^ " reloaded (deps of static ppdebug)")
    ~prod:("%." ^ ml_or_mli ^ ".depends")
    ~dep:("%." ^ ml_or_mli)
    ~insert:`top (* need to be inserted before the real ocamldep rule *)
    (fun env build ->
       let ml = env "%." ^ ml_or_mli in
       if Tags.mem "with_mlstate_debug" (tags_of_pathname ml) &&
         Sys.command ("grep -q '#<Ifstatic:' " ^ Pathname.to_string ml) = 0
       then
         tag_file ml ["with_static_preprocessing"];
       fail_rule build (* failing to that ocamlbuild calls the real ocamldep rule *)
    ) in
generate_ocamldep_rule "ml";
generate_ocamldep_rule "mli";

(* -- Macro-rules generating mlstate_platform.h files -- *)
(* TODO BUG 2 : droits du script invalides *)
(* TODO BUG 3 : path du fichier généré foireux *)
rule "mlstate_platform: () -> ocamllib/libbase/mlstate_platform.h"
  ~deps:(tool_deps mlstate_platform)
  ~prods:[libbase_dir/"mlstate_platform.h"]
  (fun env build ->
     Seq[
       Cmd(S[Sh"chmod +x"; P (libbase_dir/"gen_platform")]);
       Cmd(S[get_tool mlstate_platform; A (if is_win32 then "WIN" else "")]);
       Cmd(S[Sh"mv"; A"mlstate_platform.h"; P(libbase_dir/"mlstate_platform.h")])
     ]
  );

(* -- Opa stdlib -- *)

(*
  <!> Mathieu Fri Oct 22 10:54:50 CEST 2010
  !! IF YOU NEED TO PATCH THE FOLLOWING RULE !!
  ---> come to me, we have to talk first.
*)
let stdlib_files =
  (* keep in sync with s3passes@pass_AddStdlibFiles*)
  let core_dir = "lib/stdlib/core" in
  let tests_dir = "lib/stdlib/tests" in
  let dirs = core_dir :: tests_dir :: rec_subdirs [ core_dir ] in
  let files = List.fold_right (fun dir acc -> dir_ext_files "js" dir @ dir_ext_files "opa" dir @ acc) dirs [] in
  files
in
rule "stdlib embedded: stdlib_files -> opalib/staticsInclude.of"
  ~deps:stdlib_files
  ~prod:"compiler/opalib/staticsInclude.of"
  (fun env build -> Echo (List.map (fun f -> f^"\n") stdlib_files, "compiler/opalib/staticsInclude.of"));

let opa_opacapi_files =
  let dirs = rec_subdirs ["lib/stdlib"] in
  let files = List.fold_right (fun dir acc -> dir_ext_files "opa" dir @ acc) dirs [] in
  files
in

let opa_opacapi_plugins = ["badop"] in

(* used in mkinstall *)
let opacapi_validation = "opacapi.validation" in
rule "Opa Compiler Interface Validation (opacapi)"
  ~deps:("compiler/opa/checkopacapi.native" :: opa_opacapi_files
         @ List.map (fun x -> Printf.sprintf "lib/plugins/%s/%s.oppf" x x)
         opa_opacapi_plugins)
  ~prod:opacapi_validation
  (fun env build ->
     Cmd(S ([
              P "./compiler/opa/checkopacapi.native" ;
              A "-o" ;
              P opacapi_validation ;
            ] @ (List.rev_map (fun file -> P file) opa_opacapi_files)
            @ (List.map (fun x -> P (plugins_dir/(x ^ ".opp"))) opa_opacapi_plugins))
        )
  );

(* -- Build infos and runtime version handling -- *)

(* TODO: probably same bugs than mlstate_platform *)
let generate_buildinfos = "compiler/buildinfos/generate_buildinfos.sh" in
let version_buildinfos = "compiler/buildinfos/version_major.txt" in
let pre_buildinfos = "compiler/buildinfos/buildInfos.ml.pre" in
let post_buildinfos = "compiler/buildinfos/buildInfos.ml.post" in
let buildinfos = "compiler/buildinfos/buildInfos.ml" in
rule "buildinfos: compiler/buildinfos/* -> compiler/buildinfos/buildInfos.ml"
  ~deps:[version_buildinfos; pre_buildinfos; generate_buildinfos; post_buildinfos]
  ~prods:(buildinfos :: (if Config.is_release then ["always_rebuild"] else []))
  (fun env build ->
     let version = env version_buildinfos in
     let pre_prod = env pre_buildinfos in
     let prod = env buildinfos in
     let post_prod = env post_buildinfos in
     Seq[
       Cmd(S[Sh "cat" ; P pre_prod ; Sh ">" ; P prod]);
       Cmd(S[P "bash"; A "-e"; P generate_buildinfos; P Pathname.pwd;
             if Config.is_release then A "--release" else N;
             A "--version" ; P version ;
             Sh ">>" ; P prod]);
       Cmd(S[Sh "cat" ; P post_prod ; Sh ">>" ; P prod]);
     ]
  );

(* Warning: make sure to call this after producing the file *)
let get_version_buildinfos () =
  List.hd (string_list_of_file (opa_prefix/version_buildinfos)) in

let parser_files =
  let dir = ["compiler/opalang/classic_syntax";"compiler/opalang/js_syntax"] in
  let files = List.fold_right (fun dir acc -> dir_ext_files "trx" dir @ dir_ext_files "ml" dir) dir ["general/surfaceAst.ml"] in
  files
in
let opaParserVersion = "compiler"/"opalang"/"classic_syntax"/"opaParserVersion.ml" in
rule "opa parser version: compiler/opalang/*_syntax/* stdlib -> compiler/opalang/classic_syntax/opaParserVersion.ml"
  ~deps:parser_files
  ~prod:opaParserVersion
  (fun build env ->
    let files = List.map (fun s-> P s) parser_files in
    Seq[
      Cmd(S ( [Sh"echo let hash = \\\" > "; P (opaParserVersion)]));
      Cmd(S ( [Sh"cat"] @ files @ [Sh"|"; md5; Sh">>"; P opaParserVersion]));
      Cmd(S ( [Sh"echo \\\" >>"; P opaParserVersion ] ));
    ]
  );

let dependencies_path = "tools"/"dependencies" in
let launch_helper_script = dependencies_path/"launch_helper.sh" in
let launch_helper_js = dependencies_path/"launch_helper.js" in
let qml2js_path = "compiler"/"qml2js" in
let qml2js_file = qml2js_path/"qml2js.ml" in
let launchHelper = qml2js_path/"launchHelper.ml" in

let escape_external_content = [
  Sh"|"; Sh"sed -e 's/\\\\/\\\\\\\\/g'";
  Sh"|"; Sh"sed -e 's/\\\"/\\\\\\\"/g'";
] in

let escape_sh_comments = [
  Sh"|"; Sh"sed -e '\\%^#\\(.*\\)%d'";
] in

let escape_js_comments = [
  Sh"|"; Sh"sed -e '\\%^//\\(.*\\)%d'";
] in

rule "launchHelper: tools/dependencies/launch_helper.sh -> compiler/qml2js/launchHelper.ml"
  ~deps:[]
  ~prods:[launchHelper]
  (fun env build ->
     Seq[
       Cmd(S[Sh"mkdir"; A"-p"; P dependencies_path]);
       cp (Pathname.pwd/launch_helper_script) (opa_prefix/launch_helper_script);
       cp (Pathname.pwd/launch_helper_js) (opa_prefix/launch_helper_js);
       Cmd(S[Sh"mkdir"; A"-p"; P qml2js_path]);
       Cmd(S([Sh"echo let script = \\\" > "; P launchHelper]));
       Cmd(S([Sh"cat"; P launch_helper_script]
             @ escape_external_content
             @ escape_sh_comments
             @ [Sh">>"; P launchHelper]
            ));
       Cmd(S([Sh"echo \\\" >>"; P launchHelper]));
       Cmd(S([Sh"echo let js = \\\" >> "; P launchHelper]));
       Cmd(S([Sh"cat"; P launch_helper_js]
             @ escape_external_content
             @ escape_js_comments
             @ [Sh">>"; P launchHelper]
            ));
       Cmd(S([Sh"echo \\\" >>"; P launchHelper]));
     ]
  );


(* -- Internal use of built tools -- *)

rule " ofile"
  ~deps:("%.of" :: tool_deps "ofile")
  ~prod:"%.ml"
  (fun env build ->
     let dir = Pathname.dirname (env "%.of") in
     build_list build (string_list_of_file (env "%.of"));
     Cmd(S[get_tool "ofile"; A"-path"; P(Pathname.pwd / !Options.build_dir); P(env "%.of")]));

(* -- Proto rules -- *)

rule "proto_deps: proto -> proto.depends"
  ~dep: "%.proto"
  ~prod: "%.proto.depends"
  (proto_deps "%.proto" "%.proto.depends");

rule "proto: proto & proto_depends -> ml & mli & trx_parse"
  ~deps:("%.proto" :: "%.proto.depends" :: tool_deps "genproto")
  ~prods: [ "%.ml" ; "%.mli" ; "%_parse.trx" ]
  (fun env build ->
    let dir = Pathname.dirname (env "%.proto") in
    let proto_deps = (string_list_of_file (env "%.proto.depends")) in
    if proto_deps <> [] then build_list build proto_deps;
    Cmd(S[get_tool "genproto"
         ; P (env "%.proto")
         ; P dir
         ; P (Pathname.basename (env "%"))
         ; P (Pathname.basename (env "%") ^ "_parse")
         ]));

(* -- Wsdl2ml rules -- *)

rule "wsdl2ml: wsdl -> types.ml"
  ~deps:("%.wsdl" :: tool_deps "wsdl2ml")
  ~prods: [ "%types.ml" ]
  (fun env build ->
    let dir = Pathname.dirname (env "%.wsdl") in
    Cmd(S[get_tool "wsdl2ml"
         ; P (env "%.wsdl")
         ]));

(* -- Mlidl rules -- *)

rule "mlidl: mlidl -> types.ml & types.mli"
  ~deps:("%.mlidl" :: tool_deps "mlidl")
  ~prods: [ "%types.ml"; "%types.mli" ]
  (fun env build ->
    let dir = Pathname.dirname (env "%.mlidl") in
    Cmd(S[get_tool "mlidl"
         ; P (env "%.mlidl")
         ]));

(* -- js validation  -- *)
(*
  TODO: enable all of them as soon as possible.
*)
let google_closure_compiler_options =
  A"--warning_level"  :: A"VERBOSE"::
    (*
      Turn on every available warning as errors.
      Keep synchronized with the checker.
    *)
    (
      List.fold_left (fun acc s -> A"--jscomp_error" :: A s :: acc)
        [] [
          "accessControls" ;
          "checkRegExp" ;
          (* "checkTypes" ; *)
          "checkVars" ;
          "deprecated" ;
          "fileoverviewTags" ;
          "invalidCasts" ;
          (* "missingProperties" ; *)
          (* "nonStandardJsDocs" ; *)
          "strictModuleDepCheck" ;
          "undefinedVars" ;
          "unknownDefines" ;
          "visibility" ;
        ]
    )
in

let js_checker =
  let local = is_win32 in
  A"java" :: A"-jar"  :: (get_tool ~local "jschecker.jar") ::
    google_closure_compiler_options
in

(* -- opa plugin -- *)
(* -- plugin that fails to validate -- *)
(* TODO - Remove this and add preprocessing on plugins files before js validation *)
let accept_js_validation_failure = ["server"]
in
(* -- file that are only needed for validation process -- *)
let is_jschecker_file s =
  let suffix = ".externs.js" in
  let suflen = String.length suffix in
  let s = Pathname.basename s in
  let start = (String.length s) - suflen in
  s = "externs.js" ||
      try String.sub s start suflen = suffix with _ -> false
in
let gen_tag prefix s =
  let pfx = prefix ^ "_" in
  let lenp = String.length pfx in
  let t = try String.sub s 0 lenp = pfx with _ -> false in
  if t then Some(String.sub s lenp ((String.length s) -lenp))
  else None
in
let use_tag s = gen_tag "use" s in
let clib_tag s = gen_tag "clib" s in
let opa_plugin_builder_name = "opa-plugin-builder-bin" in
let opa_plugin_builder = get_tool opa_plugin_builder_name in

let client_lib_validation_externs = [
  "lib"/"plugins"/"opabsl"/"jsbsl"/"jquery_ext_bslanchor.externs.js";
  "lib"/"plugins"/"opabsl"/"jsbsl"/"jquery_ext_jQueryExtends.externs.js";
  "lib"/"plugins"/"opabsl"/"jsbsl"/"selection_ext_bsldom.externs.js";
  "lib"/"plugins"/"opabsl"/"jsbsl"/"jquery_extra.externs.js"
] in

let client_lib_files = [
  "compiler"/"qmljsimp"/"qmlJsImpClientLib.js";
  "compiler"/"qmlcps"/"qmlCpsClientLib.js";
  "compiler"/"qml2js"/"clientLibLib.js"
] in

let client_lib_validation_output =
  "lib"/"plugins"/"opabsl"/"js_validation"/"imp_client_lib.js" in

rule "Client lib JS validation"
  ~deps:(tool_deps "jschecker.jar" @
           tool_deps "jschecker_externals.js" @
           tool_deps "jschecker_jquery.js" @
           client_lib_validation_externs @
           client_lib_files)
  ~prod:client_lib_validation_output
 (fun env build ->
   let concat_map f l = List.concat (List.map f l) in
   Seq[
     Cmd(S [Sh"mkdir"; A"-p";P "lib/plugins/opabsl/js_validation"]);
     Cmd(S(
       js_checker @
         [A"--externs"; get_tool ~local:is_win32 "jschecker_externals.js";
          A"--externs"; get_tool ~local:is_win32 "jschecker_jquery.js"] @
         (concat_map (fun ext -> [A"--externs"; A ext])
            client_lib_validation_externs) @
         (concat_map (fun inp -> [A"--js"; P inp])
            client_lib_files) @
         [A"--js_output_file"; A client_lib_validation_output]
     ))
   ]
 );

(*
  -The documentation generator does not work if files are not suffixed with '.js'
  -But, we do not need to preprocess the opabsl_ files with ppjs,
  as for JS validation (files js_pp_bsl)
  -We simply use the files opabsl_ for generating the doc. It is obtained from
  the origin js file, and with a resolution of bsl directives (+ generation of additionnal
  type directive for the js validation

  Configuration stuff for jsdoc generator.
  Needs to access lots of files. Cf jsdocdir/README.txt
*)
let jsdocdir =
  let opageneral = Pathname.to_string Pathname.pwd in
  opageneral ^ "/tools/jsdoc-toolkit"
in

let jsdoc_target = "doc.jsbsl" in

let js_doc_input =
  (plugins_dir/"opabsl.opp"/"opabslNodeJsPackage.js") :: client_lib_files in

rule "opa-bslgenMLRuntime JS documentation"
  ~deps:(client_lib_validation_output :: js_doc_input)
  ~prod:(jsdoc_target ^ "/index.html")
  (fun env build ->
     Cmd(S(
           A"java" ::
           A("-Djsdoc.dir="^jsdocdir) ::
           A("-Djsdoc.template.dir="^jsdocdir^"/templates") ::
           A"-jar" ::
           A(jsdocdir^"/jsrun.jar") :: A(jsdocdir^"/app/run.js") ::
           A("-t="^(jsdocdir^"/templates/jsdoc")) ::
           A("--allfunctions") ::
           (* Set the target directory *)
           A("-d="^jsdoc_target) ::
           (List.map (fun js -> P js) js_doc_input)
         ))
  );

(* ------------------------------------------------------------------ *)
(* Additional rules: final compilation (compiling using our backends) *)
(* ------------------------------------------------------------------ *)

(* -- OPA compiler rules -- *)

let stdlib_packages_dir = "lib"/"stdlib" in
let build_tools_dir = "tools"/"build" in

let opaopt = try Sh(Sys.getenv "OPAOPT") with Not_found -> N in

let opacomp_deps_js = string_list_of_file (build_tools_dir/"opa-run-js-libs.itarget") in
let opacomp_deps_js_cps = string_list_of_file (build_tools_dir/"opa-run-js-cps-libs.itarget") in
let opacomp_deps_js_no_cps = string_list_of_file (build_tools_dir/"opa-run-js-no-cps-libs.itarget") in
let opacomp_deps_native = string_list_of_file (build_tools_dir/"opa-run-libs.itarget") in
let opacomp_deps_byte = List.map (fun l -> Pathname.update_extension "cma" l) opacomp_deps_native in

let opacomp_deps_native = opacomp_deps_native @ opacomp_deps_js in
let opacomp_deps_byte = opacomp_deps_byte @ opacomp_deps_js in

let opa_libs_dir = "lib" / "opa" / "static" in

let opa_share_dir = "share" / "opa" in

let copy_lib_to_runtime lib =
  let modules = string_list_of_file (lib -.- "mllib") in
  let files =
    List.fold_left
      (fun acc f ->
         let dir, modl = Pathname.dirname f, Pathname.basename f -.- "cmi" in
         List.filter (fun m -> Pathname.exists (opa_prefix / m))
           [dir / String.uncapitalize modl; dir / String.capitalize modl] @ acc)
      [] modules
  in
  let stubs =
    List.map (Pathname.update_extension !Options.ext_lib) (dir_ext_files "clib" (mlstate_lib_dir lib))
  in
  let files = stubs @ files in
  Cmd(S(link_cmd :: List.map (fun f -> P (opa_prefix / f)) files @ [ P (opa_prefix / opa_libs_dir) ]))
in

let globalizer_prods dest = [dest/"package.json"; dest/"main.js"] in
let opa_js_runtime_cps = "opa-js-runtime-cps" in
let opa_js_runtime_no_cps = "opa-js-runtime-no-cps" in

(* Convert the JS runtime to a global-prefixed nodejs package *)
let js_runtime_rule (files, dest) =
  rule ("opa js runtime " ^ dest)
    ~deps:(version_buildinfos :: tool_deps "globalizer" @ files)
    ~prods:(globalizer_prods dest)
    (fun env build ->
      let version = get_version_buildinfos () in
      Cmd(S(get_tool "globalizer" :: A"-o" :: A dest ::
            A "--package-version" :: A version ::
            List.map (fun file -> P file) files))
    )
in
List.iter js_runtime_rule [opacomp_deps_js_cps, opa_js_runtime_cps;
                           opacomp_deps_js_no_cps, opa_js_runtime_no_cps];


rule "opa run-time libraries"
  ~deps:(libbase_dir/"mimetype_database.xml" ::
            globalizer_prods opa_js_runtime_cps @
            globalizer_prods opa_js_runtime_no_cps @
            opacomp_deps_native
  )
  ~stamp:"runtime-libs.stamp"
  (fun _env _build ->
     let mllibs = List.filter (fun f -> Pathname.check_extension f "cmxa") opacomp_deps_native in
     let mllibs = List.map Pathname.remove_extension mllibs in
     let native_deps =
       List.map (fun f -> P (opa_prefix / f)) opacomp_deps_native in
     let mllibs_local =
       List.map (fun f -> P (opa_prefix / f -.- !Options.ext_lib)) mllibs in
     let copylibs = List.map copy_lib_to_runtime mllibs in
     Seq[
       Cmd(S[Sh"rm"; A"-rf"; P (opa_prefix / opa_libs_dir)]);
       Cmd(S[Sh"mkdir"; A"-p"; P (opa_prefix / opa_libs_dir)]);
       Cmd(S[Sh"rm"; A"-rf"; P (opa_prefix / opa_share_dir)]);

       Cmd(S[Sh"mkdir"; A"-p"; P (opa_prefix / opa_share_dir)]);
       Cmd(S(link_cmd :: native_deps @ [ P (opa_prefix / opa_libs_dir) ]));
       Cmd(S(link_cmd :: mllibs_local @ [ P (opa_prefix / opa_libs_dir) ]));
       Cmd(S(link_cmd ::
             P (opa_prefix / libbase_dir / "mimetype_database.xml") ::
             [ P (opa_prefix / opa_share_dir / "mimetype_database.xml") ]));
       Cmd(S[link_cmd;
             P (opa_prefix / opa_js_runtime_cps);
             P (opa_prefix / opa_libs_dir)]);
       Cmd(S[link_cmd;
             P (opa_prefix / opa_js_runtime_no_cps);
             P (opa_prefix / opa_libs_dir)]);
       Seq copylibs
     ]
  );

let opacomp build src dst_ext opt =
  build_list build
    (List.map ((/) (Pathname.dirname src)) (string_list_of_file (src-.-"depends")));
  let dst = Pathname.update_extension dst_ext src in
  Cmd(S[
        Sh("MLSTATELIBS=\""^ opa_prefix ^"\"");
        get_tool "opa-bin"; opt;
        opaopt;
        A"-o"; P dst; P src
      ])
in

rule "opa and server dependencies"
  ~deps:("runtime-libs.stamp" :: tool_deps "opa-bin")
  ~stamp:"opacomp.stamp"
  (fun env build -> Nop);

rule "opackdep: .opack -> .opack.depends"
  ~dep:"%.opack"
  ~prod:"%.opack.depends"
  (fun env build ->
     Cmd(S[P"grep"; A"-v"; A"^\\w*-"; P(env "%.opack"); Sh">"; P(env "%.opack.depends"); Sh"|| true"]));

(* A rule to build applications using the stdlib (e.g. opadoc) *)
rule "opacomp: .opack -> .native"
  ~deps: ("%.opack"::"%.opack.depends"::"opa-packages.stamp"::"opacomp.stamp"::[])
  ~prod: "%.native"
  (fun env build ->
     let dir = Pathname.dirname (env "%") in
     let mano_depends = Pathname.pwd / (env "%.depends") in
     if Pathname.exists mano_depends then (
       build_list build (List.map ((/) dir) (string_list_of_file mano_depends))
     );
     build_list build (List.map ((/) dir) (string_list_of_file (env "%.opack.depends")));
     opacomp build (env "%.opack") "native"
       (S[ A"-I" ; P stdlib_packages_dir ; A"--project-root" ; P dir; A"--parser"; A"classic";]));

rule "opacomp: .opack -> .byte"
  ~deps: ("%.opack"::"%.opack.depends"::"opa-packages.stamp"::"opacomp-byte.stamp"::[])
  ~prod: "%.byte"
  (fun env build ->
     let dir = Pathname.dirname (env "%") in
     build_list build (List.map ((/) dir) (string_list_of_file (env "%.opack.depends")));
     opacomp build (env "%.opack") "byte" (S[A"-I";P stdlib_packages_dir]));
(*
  (A"--bytecode"));
  Used to give this option to opa-bin, but since the opa package are build by ocamlbuild,
  we do not generated bytecode version of opa-packages, making the bytecode compilation
  of server not available anymore.
*)

(* temporary and unreliable *)
rule "opadep: .opa -> .opa.depends"
  ~dep: "%.opa"
  ~prod: "%.opa.depends"
  (fun env build ->
     let dep_opx_regex = "^ *import  \\*\\(.\\+\\) *$" in
     let dep_opp_regex = "^ *import-plugin  \\*\\(.\\+\\) *$" in
     let sed_dep dep_regex redir dest = S[sed; A"-n"; A("s%"^dep_regex^"%\\1.opx%p"); P(env "%.opa"); Sh redir; P dest] in
     Seq[
       Cmd(sed_dep dep_opp_regex ">" (env "%.opa.depends"));
       Cmd(sed_dep dep_opx_regex ">>" (env "%.opa.depends"))
     ]
  )
;

rule "opacomp: .opa -> .native"
  ~deps: ("%.opa"::"%.opa.depends"::"opacomp.stamp"::[])
  ~prod: "%.native"
  (fun env build -> opacomp build (env "%.opa") "native" N);

rule "opacomp: .opa -> .byte"
  ~deps: ("%.opa"::"%.opa.depends"::"opacomp-byte.stamp"::[])
  ~prod: "%.byte"
  (fun env build -> opacomp build (env "%.opa") "byte" (A"--bytecode"));

rule "opa bash_completion: opa-bin -> bash_completion"
  ~deps: (tool_deps "opa-bin")
  ~prod: "bash_completion"
  (fun env build ->
     Seq[Cmd(S[get_tool "opa-bin"; A"--bash-completion"])]);


(************************************************)
(* OPA PLUGINS (OPP) ****************************)

(** Generates a rule to build the [name] Opa plugin *)
let plugin_building name =
  (* Plugins paths *)
  let path        = plugins_dir/name in
  let opp         = path -.- "opp" in
  let oppf        = path/name -.- "oppf" in
  let opa_plugin  = path/name -.- "opa_plugin" in
  let tags = tags_of_pathname opa_plugin in
  let files = string_list_of_file opa_plugin in
  let files = List.map (fun file -> path/file) files in

  (* Plugins options *)
  let options = A "-o" :: A name :: A "--build-dir" :: A plugins_dir :: [] in
  let options (* Ocaml libs*) = Tags.fold
    (fun tag options -> match use_tag tag with
     | None -> options
     | Some d ->
         let dir = match mlstate_lib_dir d with
           | "." -> "+"^d
           | dir -> opa_prefix/dir
         in
         A "--ml" :: A "-I" :: A "--ml" :: P dir :: options
    ) tags options
  in
  let options (* C libs *) = Tags.fold
    (fun tag options ->
       match clib_tag tag with
       | None -> options
       | Some dep ->
           if not (is_system_libs dep) then
             A "--ml" :: A "-cclib" :: A "--ml" :: A ("-l"^dep) :: options
           else options
    ) tags options
  in
  let has_node, options (* JavaScript files *) =
    let jsfiles =
      List.filter
        (fun f -> Pathname.check_extension f "js" || Pathname.check_extension f "nodejs")
        files in
    let options = List.fold_left
      (fun options jsfile ->
           match is_jschecker_file jsfile with
           | true -> A "--js-validator-file" :: P jsfile :: options
           | false ->
               P jsfile ::
               match Tags.mem "with_mlstate_debug" (tags_of_pathname jsfile) with
               | true -> A "--pp-file" ::
                   P (Printf.sprintf "%s:%s" jsfile
                        (string_of_command_spec (get_tool"ppjs"))) :: options
               | false -> options
      ) options (List.rev jsfiles)
    in
    (* Specify the JavaScript validator *)
    (List.exists (fun f -> Pathname.check_extension f "nodejs") jsfiles),
    if jsfiles = [] then options
    else match js_checker with
    | [] -> []
    | t::q ->
        (* TODO : Remove unsafe-js *)
        A "--unsafe-js" :: A "--js-validator" :: t
        :: List.fold_right (fun opt acc -> A"--js-validator-opt"::opt::acc) q options
  in
  let options =
    let conf_files =
      List.filter (fun f ->
        Pathname.check_extension f "jsconf" ||
          Pathname.check_extension f "nodejsconf"
      ) files in
    List.map (fun file -> P file) conf_files @ options in
  let has_ml, options (* OCaml files *) =
    let mlfiles = List.filter (fun f -> Pathname.check_extension f "ml") files in
    (mlfiles <> [],
     List.fold_left
       (fun options mlfile ->
          P mlfile ::
            match Tags.mem "with_mlstate_debug" (tags_of_pathname mlfile) with
            | true ->
                A"--pp-file"
                :: P (Printf.sprintf "%s:%s" mlfile (Pathname.pwd/"tools"/"utils"/"ppdebug.pl"))
                :: options
            | false -> options
       ) options (List.rev mlfiles)
    )
  in
  let options (* Opa files *) =
    List.map (fun p -> P p) (List.filter (fun f -> Pathname.check_extension f "opa") files)
    @ options
  in
  let is_static = Tags.mem "static" (tags_of_pathname path) in
  let options =
    if is_static then
      A "--static" :: A "--no-build" :: options
    else options
  in

  let options = A "--js-bypass-syntax" :: A "new" :: options in

  (* Hack for opabsl *)
  let postlude = [] in
  let prods = [] in
  let prods, files, postlude =
    if name = "opabsl" then
      ("serverLib.mli"::prods, path/"serverLib.mli"::files,
       (ln_f (path/"serverLib.mli") (opp/"serverLib.mli")) :: postlude
      )
    else (prods, files, postlude)
  in

  (* Plugins productions *)
  let prod_suffix suffix =
    Printf.sprintf "%s%s" name suffix
  in
  let prods =
    if has_ml then
      prod_suffix "MLRuntime.ml" :: prod_suffix "MLRuntime.mli" :: prods
    else prods
  in
  let prods =
    if has_node then
      prod_suffix "NodeJsPackage.js" :: prods
    else prods
  in
  let prods =
    if is_static then (
      let prods =
        prod_suffix "Plugin.ml" :: prod_suffix "Loader.ml" :: prods
      in
      (* Tags all produced files (in %.opp) as file in (%) *)
      List.iter
        (fun file ->
           let tags = Tags.elements (tags_of_pathname (path/file)) in
           tag_file (opp/file) tags;

        ) prods;
      prods
    )
    else prods
  in
  let prods = List.map (fun file -> opp/file) prods in
  let prods = prods in

  (* Plugins deps *)
  let deps =
    files @ (tool_deps "jschecker.jar") @ (tool_deps "ppdebug") @
      (tool_deps "ppjs") @ (tool_deps opa_plugin_builder_name)
  in
  let deps (* Ocaml libs*) =
    let parent s =
      String.sub s 0 (String.rindex s '/')
    in
    Tags.fold
    (fun tag deps -> match use_tag tag with
     | None -> deps
     | Some lib ->
         match mlstate_lib_dir lib with
         | "." -> deps
         | dir -> ((parent dir)/lib^".cmxa") :: deps
    ) tags deps
  in

  rule (Printf.sprintf "Opa plugin: %s" name)
    ~deps
    ~prods
    ~stamp:oppf
    (fun env build ->
       let opp_build =
         Cmd (S (Sh("MLSTATELIBS=\""^ opa_prefix ^"\"") ::
               opa_plugin_builder::options
            ))
       in
       (Seq (opp_build :: postlude))
    )
in

(** Script which generates the a file which contains the list of all Opa plugins
    name ([all_plugins_file}) *)
let make_all_plugins = stdlib_packages_dir/"all_plugins.sh" in

(** The all plugins file, list of all Opa plugins *)
let all_plugins_file = stdlib_packages_dir/"all.plugins" in

(** Build here because the rule is always wanted. *)
let () = List.iter
  plugin_building
  [ "opabsl"; ]
  (*   "badop"; *)
  (*   "browser_canvas"; "crypto"; "gcharts"; "hlnet"; "iconv"; *)
  (*   "irc"; "mail"; "mongo"; "qos"; "server"; "socket"; "unix" *)
  (* ] *)
in

(** This rule generates rules for all plugins *)
let lazy_plugin_rules =
  lazy (
    let all_plugins_file = opa_prefix / all_plugins_file in
    Command.execute ~quiet:true ~pretend:false
      (Cmd (S[
        Sh"mkdir"; A"-p"; P (opa_prefix / stdlib_packages_dir); Sh"&&";
        Sh"cd"; P (Pathname.pwd / stdlib_packages_dir); Sh"&&";
        P"./all_plugins.sh"; Sh">"; P all_plugins_file;
      ])) ;
    let plugins = string_list_of_file all_plugins_file in
    List.iter plugin_building plugins
  )
in


(* -- OPA packages -- *)

let package_to_dir s0 =
  let s = String.copy s0 in
  for i = 0 to String.length s - 1 do
    if s.[i] = '.' then s.[i] <- '/'
  done;
  s
in

let dir_to_package s0 =
  let s = String.copy s0 in
  let len_std = String.length stdlib_packages_dir in
  let pfx,s = (* remove optional stdlib_packages_dir prefix *)
    try
      let pfx = String.sub s 0 len_std in
      if pfx = stdlib_packages_dir
      then pfx, String.sub s (len_std + 1) (String.length s - len_std - 1)
      else "", s
    with Invalid_argument _ -> "", s
  in
  for i = 0 to String.length s - 1 do
    if s.[i] = '/' then s.[i] <- '.'
  done;
  pfx, s
in

let module RuleFailure = struct exception E end in
let files_of_package pkg =
  let pkdir = "lib" / package_to_dir pkg in
  if not (Pathname.is_directory (Pathname.pwd / pkdir)) then
    let () = Printf.eprintf "Error: can not find sources for package %s (directory %s does not exist)\n" pkg pkdir in
    raise RuleFailure.E
  else
    let opack = dir_ext_files "opack" (Pathname.pwd / pkdir) in
    let files = dir_ext_files "opa" (Pathname.pwd / pkdir) in
    let files = files @ opack in
    (*
      return relative filenames
    *)
    let files =
      let len = String.length Pathname.pwd + 1 in (* the additinal '/' *)
      let relative_part s = String.sub s len (String.length s - len) in
      List.map relative_part files
    in
    (*
      When you compare 2 branches, if the order of opa sources is not deterministic, you can become crazy
    *)
    let files = List.sort String.compare files in
    files in

let packages_exclude_node = "node.exclude"in
let packages_exclude_qmlflat = "qmlflat.exclude"in
let make_all_packages = [stdlib_packages_dir/"all_packages.sh"; stdlib_packages_dir/packages_exclude_node ; stdlib_packages_dir/packages_exclude_qmlflat] in
let all_packages_file nodebackend = if nodebackend then stdlib_packages_dir/"all.node.packages" else stdlib_packages_dir/"all.packages" in

let all_packages_building nodebackend =
  let prod = all_packages_file nodebackend in
  rule (if nodebackend then "all.node.packages" else "all.packages")
    ~deps: make_all_packages
    ~prod
    (fun env build ->
         Cmd(S[
               Sh"cd"; P (Pathname.pwd / stdlib_packages_dir); Sh"&&";
               P"./all_packages.sh"; P (if nodebackend then packages_exclude_node else packages_exclude_qmlflat); Sh">"; P (Pathname.pwd / !Options.build_dir / prod);
             ])
    )
in

all_packages_building true;
all_packages_building false;



let opa_create_prefix = "tools/opa-create/src/opa-create" in
let opa_create_src = opa_create_prefix ^ ".opa" in
let opa_create_dst = opa_create_prefix ^ ".exe" in

let dir_all_files dir =
  List.filter (fun p -> (not (Pathname.is_directory p))) (dirlist dir)
in

let dir_rec_all_files dir =
  let dirs =  rec_subdirs [ dir ] in
  List.fold_right (fun dir acc -> dir_all_files dir @ acc) dirs []
in

rule "opa application creator"
  ~deps:(dir_rec_all_files "tools/opa-create")
  ~prods: [opa_create_dst]
  (fun env build ->
      Cmd(S[
	(Sh ("MLSTATELIBS=\""^ opa_prefix ^"\""));
        get_tool "opa-bin";
        A"-o"; P opa_create_dst; P opa_create_src;
        A"--opx-dir"; A "stdlib.qmljs";
        A"--no-server";
        A"-I"; A plugins_dir
      ]));

let package_building ?(nodebackend=false) ~name ~stamp ~stdlib_only ~rebuild () =
  Lazy.force lazy_plugin_rules;
  let plugins = string_list_of_file (opa_prefix / all_plugins_file) in
  let plugins = List.map (fun f -> plugins_dir/f/f -.- "oppf") plugins in
  rule name
    ~deps:(plugins @ [
      opacapi_validation;
      version_buildinfos;
      all_packages_file nodebackend;
      "opacomp.stamp"
    ])
    ~stamp
    ~prod:"i_dont_exist" (* forces ocamlbuild to always run the command *)
  (fun env build ->
     try
       let packages = string_list_of_file (all_packages_file nodebackend) in
       let packages =
         if stdlib_only
         then
           let stdlib = "stdlib.core" in
           List.filter (fun package ->
                          String.length package >= String.length stdlib &&
                            stdlib = String.sub package 0 (String.length stdlib)) packages
         else packages in
       let list_package_files = List.map
         (fun pkg ->
            let files = files_of_package pkg in
            (*
              Copy in _build the opa files of the packages.
              In this way, files given to the compiler are relative,
              and api files are generated in the _build
              This makes also that the packages does not contain absolute filename,
              which is not valid wrt the deb checker.
            *)
            build_list build files;
            (pkg, files)) packages in
       let conf =
         List.concat (
           List.map
             (fun (pkg, files) ->
                (pkg ^ ":\n") ::
                  (
                    (* auto import *)
                    let prefix = "stdlib.core" in
                    let len = String.length prefix in
                    if String.length pkg >= String.length prefix && String.sub pkg 0 len = prefix
                    then (
                      if pkg = prefix
                      then ""
                      else
                        (* subdirectory of stdlib.core import stdlib.core *)
                         "  import stdlib.core\n"
                    )
                    else "  import stdlib.core\n  import stdlib.core.*\n"
                  ) ::
                  List.map (fun file -> "  " ^ file ^ "\n") files)
             list_package_files
         ) in
       let all_files =
         (*List.concat (List.map (fun (_,files) -> List.map (fun f -> P f) files) list_package_files)*)
         [A"--conf-opa-files"]
       in
       let opx_dir = if nodebackend then "stdlib.qmljs" else "stdlib.qmlflat" in
       let version = get_version_buildinfos () in
       let extra_opt = if rebuild then [A"--rebuild"] else [] in
       let extra_opt =
         [A"--opx-dir";A opx_dir;
          A"--package-version"; A version;
          A"--warn-error";A"root";
          A"--no-warn-error";A"coding.deprecated";
          A"--no-warn-error";A"load-opx";
          A"--no-warn-error";A"load-import";
          A"--no-warn-error";A"bsl.loading";
          A"--no-warn-error";A"bsl.projection";
          A"--warn"; A"jscompiler";
         ] @
           if nodebackend then
             A"--back-end"::A"qmljs"::extra_opt
           else A"--back-end"::A"qmlflat"::extra_opt
       in
       Seq[
         Echo(conf, "conf");
         Cmd(S([Sh"mkdir";A"-p";P opx_dir;]));
         Cmd(S([Sh"rm -rf";P (opx_dir/"*.opp")]));
         Cmd(S([Sh("MLSTATELIBS=\""^ opa_prefix ^"\"");
                get_tool "opa-bin";
                A"--autocompile";
                (* A"--verbose-build"; *)
                A"--conf";P "conf";
                A"--slicer-check"; A "low";
                A"--project-root"; P Pathname.pwd; (* because the @static_resource in the stdlib expect this *)
                A"--no-stdlib";
                A"--parser"; A"classic";
                A"--opx-dir"; P opa_prefix;
                A"-I"; A plugins_dir;
                opaopt;
                S all_files;
               ] @ extra_opt));
       ]
     with RuleFailure.E ->
       fail_rule build
  ) in

package_building
  ~name:"opa-packages: meta-rule to build all .opx"
  ~stamp:"opa-packages.stamp"
  ~stdlib_only:false
  ~rebuild:false
  ();

package_building
  ~name:"opa-stdlib-packages: meta-rule to build all the stdlib .opx"
  ~stamp:"opa-stdlib-packages.stamp"
  ~stdlib_only:true
  ~rebuild:false
  ();

package_building
  ~name:"opa-node-packages: meta-rule to build all the stdlib .opx"
  ~stamp:"opa-node-packages.stamp"
  ~stdlib_only:false
  ~nodebackend:true
  ~rebuild:false
  ();

rule "opa-both-packages"
  ~deps:["opa-node-packages.stamp"; "opa-packages.stamp"]
  ~stamp:"opa-both-packages.stamp"
  (fun env build -> Nop);

() (* This file should be an expr of type unit *)
