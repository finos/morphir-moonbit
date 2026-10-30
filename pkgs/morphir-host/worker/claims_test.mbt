///|
test "extension identities are validated values" {
  assert_eq(
    @worker.ExtensionId::parse("morphir-moonbit").to_string(),
    "morphir-moonbit",
  )
  for text in ["", "morphir moonbit", "morphir\nmoonbit", "x".repeat(129)] {
    guard (Ok(@worker.ExtensionId::parse(text)) catch { e => Err(e) })
      is Err(InvalidExtensionId(_)) else {
      fail("accepted extension ID \{text}")
    }
  }
  assert_eq(
    @worker.ExtensionVersion::parse("0.4.2-rc.1").to_string(),
    "0.4.2-rc.1",
  )
  for text in ["", "0.4 .2", "1".repeat(65)] {
    guard (Ok(@worker.ExtensionVersion::parse(text)) catch { e => Err(e) })
      is Err(InvalidExtensionVersion(_)) else {
      fail("accepted version \{text}")
    }
  }
}

///|
test "claims record identity, version and capabilities" {
  let claims = @worker.Claims::new(
    @worker.ExtensionId::parse("morphir-moonbit"),
    @worker.ExtensionVersion::parse("0.1.0"),
    [Frontend, Backend],
  )
  assert_eq(claims.extension_id.to_string(), "morphir-moonbit")
  assert_true(claims.capabilities.contains(Backend))
  assert_eq(@worker.Capability::parse("frontend"), Frontend)
  guard (Ok(@worker.Capability::parse("linter")) catch { e => Err(e) })
    is Err(UnknownCapability(_)) else {
    fail("accepted an unknown capability")
  }
}

///|
test "protocol lines are the two MEP versions the host offers" {
  assert_eq(@worker.ProtocolLine::parse("0.1"), Mep0_1)
  assert_eq(@worker.ProtocolLine::parse("0.2.0-draft.1"), Mep0_2Draft1)
  assert_eq(@worker.ProtocolLine::Mep0_2Draft1.to_string(), "0.2.0-draft.1")
  guard (Ok(@worker.ProtocolLine::parse("0.2.0")) catch { e => Err(e) })
    is Err(UnknownProtocolLine(_)) else {
    fail("accepted a protocol version the host does not offer")
  }
}

///|
test "a model tuple has five closed parts" {
  let tuple = @worker.ModelTuple::new(
    CompileModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    V4_0_0,
  )
  assert_eq(tuple.operation.to_string(), "morphir.frontend.compileModel")
  assert_eq(tuple.profile.to_string(), "morphir-ir")
  assert_eq(tuple.codec.to_string(), "morphir-json")
  assert_eq(tuple.envelope_version.to_string(), "0.1.0-draft.1")
  assert_eq(tuple.ir_version.to_string(), "4.0.0")
  assert_eq(
    @worker.ModelTuple::parse(
      "morphir.backend.generateModel", "morphir-model", "ion-binary", "0.1.0-draft.1",
      "4.0.0",
    ),
    @worker.ModelTuple::new(
      GenerateModel,
      MorphirModel,
      IonBinary,
      V0_1_0Draft1,
      V4_0_0,
    ),
  )
  guard (Ok(
      @worker.ModelTuple::parse(
        "morphir.frontend.compileModel", "morphir-ir", "ion-text", "0.1.0-draft.1",
        "4.0.0",
      ),
    ) catch {
      e => Err(e)
    })
    is Err(UnknownModelTuplePart(_)) else {
    fail("accepted an unknown codec")
  }
}
