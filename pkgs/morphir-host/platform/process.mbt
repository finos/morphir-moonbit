///|
#cfg(target="native")
fn process_result(code : Int, output : String, error : String) -> Json {
  Json::object(
    Map::from_array([
      ("exitCode", Json::number(code.to_double())),
      ("stdout", Json::string(output)),
      ("stderr", Json::string(error)),
    ]),
  )
}
