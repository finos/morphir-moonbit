///|
fn main raise {
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let historical = @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("historical"), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("main"),
          {
            access: @ir.Access::Public,
            value: {
              types: Map([]),
              doc: None,
              values: Map::from_array([
                (
                  @ir.Name::parse("answer"),
                  @fixtures.definition(
                    int,
                    @ir.Value::Literal(
                      { ..@fixtures.attrs(), inferred_type: Some(int), },
                      @ir.Literal::IntegerLiteral("42"),
                    ),
                  ),
                ),
              ]),
            },
          },
        ),
      ]),
    }),
  )
  let result = @generator.generate(
    @generator.Input::new(
      "pricing-acceptance",
      @ir_json.read(@ir_json.write(@fixtures.acceptance_library())),
    ),
  )
  println(
    Json::object(
      Map::from_array([
        ("moduleName", Json::string(result.project.module_name)),
        (
          "invocationSuite",
          Json::array(
            @execution.Suite::from_json({
              "profile": "morphir-invocations-v1",
              "calls": [
                {
                  "id": "subtract",
                  "entry": "calls:main#subtract",
                  "arguments": [
                    { "type": "int", "value": "9007199254741035" },
                    { "type": "int", "value": "9007199254740993" },
                  ],
                },
              ],
            })
            .encode("ion-binary")
            .to_array()
            .map(b => Json::number(b.to_int().to_double())),
          ),
        ),
        (
          "invocationSuite2",
          Json::array(
            @execution.Suite::from_json({
              "profile": "morphir-invocations-v1",
              "calls": [
                {
                  "id": "subtract",
                  "entry": "calls:main#subtract",
                  "arguments": [
                    { "type": "int", "value": "45" },
                    { "type": "int", "value": "3" },
                  ],
                },
              ],
            })
            .encode("ion-binary")
            .to_array()
            .map(b => Json::number(b.to_int().to_double())),
          ),
        ),
        ("pricingIR", Json::string(@ir_json.write(@fixtures.pricing()))),
        ("conformanceIR", Json::string(@ir_json.write(@fixtures.conformance()))),
        (
          "rustConformanceIR",
          Json::string(@ir_json.write(@fixtures.rust_conformance())),
        ),
        (
          "rustClassicIR",
          Json::string(
            @versioned_json.write(
              @migration.migrate(
                @versioned.V4(@fixtures.rust_conformance()),
                @version.FormatVersion::baseline(3U),
              ),
            ),
          ),
        ),
        (
          "invocationIR",
          Json::string(@ir_json.write(@fixtures.invocation_library())),
        ),
        (
          "historicalSources",
          Json::array(
            [1U, 2U, 3U].map(major => {
              Json::string(
                @versioned_json.write(
                  @migration.migrate(
                    @versioned.V4(historical),
                    @version.FormatVersion::baseline(major),
                  ),
                ),
              )
            }),
          ),
        ),
        (
          "sourceIR",
          Json::string(@ir_json.write(@fixtures.acceptance_library())),
        ),
        (
          "symbols",
          Json::array(
            result.symbols.map(symbol => {
              Json::object(
                Map::from_array([
                  ("fqname", Json::string(symbol.fqname)),
                  ("name", Json::string(symbol.generated_name)),
                  ("public", Json::boolean(symbol.public)),
                ]),
              )
            }),
          ),
        ),
        (
          "artifacts",
          Json::array(
            result.artifacts.map(artifact => {
              Json::object(
                Map::from_array([
                  ("path", Json::string(artifact.path)),
                  (
                    "content",
                    match artifact.content {
                      Text(text) => Json::string(text)
                      Binary(bytes) =>
                        Json::array(
                          bytes
                          .to_array()
                          .map(byte => Json::number(byte.to_int().to_double())),
                        )
                    },
                  ),
                ]),
              )
            }),
          ),
        ),
      ]),
    ).stringify(),
  )
}
