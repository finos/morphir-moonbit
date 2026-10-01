///|
fn invocation_snapshot(files : Array[@moonbit.Artifact]) -> String {
  let sorted = files.copy()
  sorted.sort_by(fn(a, b) { a.path.compare(b.path) })
  Json::array(
    sorted.map(a => {
      Json::array([
        Json::string(a.path),
        match a.content {
          Text(s) => Json::array([Json::string("text"), Json::string(s)])
          Binary(b) =>
            Json::array([
              Json::string("binary"),
              Json::array(
                b.to_array().map(v => Json::number(v.to_int().to_double())),
              ),
            ])
        },
      ])
    }),
  ).stringify()
}

///|
fn entry_manifest(plan : @execution.Plan) -> String {
  Json::array(
    plan.library.invocations.map(e => {
      (
        {
          "fqname": e.fqname,
          "generatedName": e.generated_name,
          "inputs": e.inputs.map(t => t.name()),
          "output": e.output.name(),
        } : Json)
    }),
  ).stringify()
}

///|
fn js_driver_main() -> Array[@moonbit.Artifact] {
  let source =
    #|///|
    #|#module("node:fs")
    #|extern "js" fn read(path : String) -> Bytes = "readFileSync"
    #|///|
    #|#module("node:fs")
    #|extern "js" fn write(path : String, bytes : Bytes) -> Unit = "writeFileSync"
    #|///|
    #|extern "js" fn arg(i : Int) -> String = "i => process.argv[i]"
    #|///|
    #|fn main {
    #|  try {
    #|    let suite = @execution.Suite::decode(read(arg(2)), "ion-binary")
    #|    let values = suite.calls.map(call => @execution.record([
    #|      ("id",@ion.IonValue::string(call.id)),
    #|      ("value",@driver.invoke(call).to_ion()),
    #|    ]))
    #|    write(arg(3),@binary.write_binary_value(@execution.record([
    #|      ("profile",@ion.IonValue::string("morphir-outcomes-v1")),
    #|      ("suite_identity",@ion.IonValue::string(arg(4))),
    #|      ("calls",@ion.IonValue::list(values)),
    #|    ])))
    #|  } catch { error => abort(error.to_string()) }
    #|}
    #|
  [
    { path: "main/main.mbt", role: Source, content: Text(source), },
    {
      path: "main/moon.pkg",
      role: PackageManifest,
      content: Text(
        "pkgtype(kind: \"executable\")\nimport {\n\"morphir-generated/driver\" @driver,\n\"finos/morphir-execution\" @execution,\n\"moonrockz/ion/ion\",\n\"moonrockz/ion/binary\",\n}\n",
      ),
    },
  ]
}

///|
/// An explicit process session owns scratch state until disposal, including failed builds.
pub fn process_execution(
  program : String,
  helper : String,
  compiler_home : String,
  dependencies : Map[String, String],
  timeout? : Int = 120000,
) -> @execution.Provider raise {
  if !@platform.process_supported() ||
    program == "" ||
    helper == "" ||
    compiler_home == "" ||
    timeout < 1 ||
    timeout > 600000 {
    raise @config.Invalid("execution.provider_required")
  }
  let supplied = dependencies.copy()
  {
    targets: ["js"],
    acquire: fn() raise {
      let directory = @platform.temporary()
      let id = @identity.sha256(@utf8.encode(directory))
      let mut disposed = false
      let mut built : Json? = None
      fn request(fields : Map[String, Json]) -> Json raise {
        if disposed {
          raise @config.Invalid("execution.disposed")
        }
        fields["leaseId"] = Json::string(id)
        fields["timeout"] = Json::number(
          (if timeout < 10 { 1 } else { timeout * 9 / 10 }).to_double(),
        )
        let path = directory + "/request.json"
        @platform.write(path, Json::object(fields).stringify())
        let result = @platform.process(
          program,
          [helper, path],
          @platform.cwd(),
          "",
          timeout,
        )
        if build_field(result, "exitCode") != Json::number(0.0) {
          raise @config.Invalid(
            "execution.provider_failed: " + build_text(result, "stderr"),
          )
        }
        @wire.parse(build_text(result, "stdout"))
      }
      {
        id,
        build: fn(plan) raise {
          if built is Some(_) {
            raise @config.Invalid("execution.already_built")
          }
          let snapshot = invocation_snapshot(plan.library.artifacts)
          let driver_files = plan.driver + js_driver_main()
          let deps = plan.library.project.dependencies.map(d => @engine.ProjectDependency::{
            module_name: d.module_name,
            version: d.version,
            api_profile: d.api_profile,
            semantic_pin: d.semantic_pin,
          })
          for
            (module_name, version, api_profile, semantic_pin) in [
              (
                "finos/morphir-execution", "0.1.0", "morphir-invocations-v1", "morphir-invocations-v1",
              ),
              ("moonrockz/ion", "0.3.0", "ion-v1", "ion-0.3.0"),
              ("moonbitlang/x", "0.5.5", "moonbit-x", "x-0.5.5"),
              ("moonbitlang/async", "0.22.4", "moonbit-async", "async-0.22.4"),
            ] {
            deps.push({ module_name, version, api_profile, semantic_pin, })
          }
          let project : @engine.LibraryProject = {
            id: plan.library.project.module_name,
            source: plan.unit.id,
            root: "generated",
            members: plan.library.project.members,
            dependencies: deps,
            build_contract: "moonbit-library-v1",
            policy: @engine.Required(plan.target),
          }
          let source_identity = @identity.sha256(@utf8.encode(snapshot))
          let driver = invocation_snapshot(driver_files)
          let manifest = entry_manifest(plan)
          let result = request(
            Map::from_array([
              ("operation", Json::string("build")),
              ("projectId", Json::string(project.id)),
              ("contract", Json::string(project.build_contract)),
              ("snapshot", Json::string(snapshot)),
              ("sourceIdentity", Json::string(source_identity)),
              ("target", Json::string(plan.target)),
              ("driver", Json::string(driver)),
              ("manifest", Json::string(manifest)),
              ("compilerHome", Json::string(compiler_home)),
              (
                "suppliedDependencies",
                Json::object(supplied.map(fn(_, path) { Json::string(path) })),
              ),
              (
                "dependencies",
                Json::array(
                  deps.map(d => {
                    (
                      {
                        "moduleName": d.module_name,
                        "version": d.version,
                        "apiProfile": d.api_profile,
                        "semanticPin": d.semantic_pin,
                      } : Json)
                  }),
                ),
              ),
            ]),
          )
          validate_evidence(
            { project, snapshot, source_identity, target: plan.target, },
            id,
            result,
          )
          if build_text(result, "driverIdentity") !=
            @identity.sha256(@utf8.encode(driver)) ||
            build_text(result, "manifestIdentity") !=
            @identity.sha256(@utf8.encode(manifest)) ||
            !digest_shape(build_text(result, "executableIdentity")) ||
            !digest_shape(build_text(result, "runtimeIdentity")) {
            raise @config.Invalid("execution.evidence_mismatch")
          }
          built = Some(result)
          result
        },
        invoke: fn(suite) raise {
          guard built is Some(evidence) else {
            raise @config.Invalid("execution.not_built")
          }
          if disposed {
            raise @config.Invalid("execution.disposed")
          }
          let bytes = suite.encode("ion-binary")
          let suite_identity = @identity.sha256(bytes)
          let output = directory + "/outcomes.ionb"
          if @platform.kind(output) != 0 {
            @platform.remove_file(output)
          }
          @platform.write_bytes(directory + "/suite.ionb", bytes)
          let result = request(
            Map::from_array([
              ("operation", Json::string("invoke")),
              ("suiteIdentity", Json::string(suite_identity)),
            ]),
          )
          if build_text(result, "leaseId") != id ||
            build_text(result, "suiteIdentity") != suite_identity ||
            build_text(result, "executableIdentity") !=
            build_text(evidence, "executableIdentity") {
            raise @config.Invalid("execution.evidence_mismatch")
          }
          let bytes = @platform.read_bytes(output)
          if bytes.length() > 1048576 {
            raise @config.Invalid("execution.output_limit")
          }
          let f = @protocol.fields(@ion_binary.read_binary_value(bytes[:]), [
            "profile", "suite_identity", "calls",
          ])
          if @protocol.string(@protocol.required(f, "profile")) !=
            "morphir-outcomes-v1" ||
            @protocol.string(@protocol.required(f, "suite_identity")) !=
            suite_identity {
            raise @config.Invalid("execution.outcome_identity")
          }
          guard @protocol.required(f, "calls").kind() is List(calls) else {
            raise @config.Invalid("execution.outcomes_list")
          }
          if calls.length() != suite.calls.length() {
            raise @config.Invalid("execution.result_count")
          }
          let values = []
          for i = 0; i < calls.length(); i = i + 1 {
            let f = @protocol.fields(calls[i], ["id", "value"])
            if @protocol.string(@protocol.required(f, "id")) !=
              suite.calls[i].id {
              raise @config.Invalid("execution.call_identity")
            }
            values.push(
              @protocol.Value::from_ion(@protocol.required(f, "value")),
            )
          }
          { values, evidence: result, }
        },
        dispose: fn() raise {
          if !disposed {
            disposed = true
            dispose_build_tree(directory)
          }
        },
      }
    },
  }
}
