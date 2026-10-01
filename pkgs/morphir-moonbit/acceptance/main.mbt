///|
fn main raise {
  let result = @generator.generate(
    @generator.Input::new("scalar-acceptance", @fixtures.pricing()),
  )
  println(
    Json::object(
      Map::from_array([
        ("moduleName", Json::string(result.project.module_name)),
        ("sourceIR", Json::string(@ir_json.write(@fixtures.pricing()))),
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
