///|
/// The extension ID a guest reports: 1 to 128 printable ASCII characters
/// without spaces.
pub struct ExtensionId {
  priv text : String
} derive(Eq, Debug)

///|
pub extend ExtensionId with Eq::{equal, not_equal}

///|
pub extend ExtensionId with @debug.Debug::{to_repr}

///|
fn printable_token(text : String, limit : Int32) -> Bool {
  text.length() > 0 &&
  text.length() <= limit &&
  text.iter().all(c => c > ' ' && c <= '~')
}

///|
pub fn ExtensionId::parse(text : String) -> ExtensionId raise ValueError {
  guard printable_token(text, 128) else { raise InvalidExtensionId(text) }
  { text, }
}

///|
pub impl Show for ExtensionId with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend ExtensionId with Show::{to_string, output}

///|
/// The extension version a guest reports: 1 to 64 printable ASCII characters
/// without spaces. The host compares versions for equality only.
pub struct ExtensionVersion {
  priv text : String
} derive(Eq, Debug)

///|
pub extend ExtensionVersion with Eq::{equal, not_equal}

///|
pub extend ExtensionVersion with @debug.Debug::{to_repr}

///|
pub fn ExtensionVersion::parse(
  text : String,
) -> ExtensionVersion raise ValueError {
  guard printable_token(text, 64) else { raise InvalidExtensionVersion(text) }
  { text, }
}

///|
pub impl Show for ExtensionVersion with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend ExtensionVersion with Show::{to_string, output}

///|
/// A language an extension's frontend claims, with the source file
/// extensions it compiles. Both come from the extension; the host keeps no
/// list of languages.
pub struct LanguageClaim {
  language_id : @ids.LanguageId
  file_extensions : Array[@ids.FileExtension]
} derive(Eq, Debug)

///|
pub extend LanguageClaim with Eq::{equal, not_equal}

///|
pub extend LanguageClaim with @debug.Debug::{to_repr}

///|
pub fn LanguageClaim::new(
  language_id : @ids.LanguageId,
  file_extensions : Array[@ids.FileExtension],
) -> LanguageClaim {
  { language_id, file_extensions, }
}

///|
/// What an extension says it is and does. Claims describe a guest; they do
/// not grant it execution authority.
pub struct Claims {
  extension_id : ExtensionId
  version : ExtensionVersion
  languages : Array[LanguageClaim]
  operations : Array[Operation]
} derive(Eq, Debug)

///|
pub extend Claims with Eq::{equal, not_equal}

///|
pub extend Claims with @debug.Debug::{to_repr}

///|
pub fn Claims::new(
  extension_id : ExtensionId,
  version : ExtensionVersion,
  languages~ : Array[LanguageClaim],
  operations~ : Array[Operation],
) -> Claims {
  { extension_id, version, languages, operations, }
}

///|
pub fn Claims::offers(self : Claims, operation : Operation) -> Bool {
  self.operations.contains(operation)
}

///|
/// The MEP versions the host offers. MEP 0.1 carries the legacy compile and
/// generate methods; MEP 0.2.0-draft.1 carries the model methods.
pub(all) enum ProtocolLine {
  Mep0_1
  Mep0_2Draft1
} derive(Eq, Debug)

///|
pub extend ProtocolLine with Eq::{equal, not_equal}

///|
pub extend ProtocolLine with @debug.Debug::{to_repr}

///|
pub fn ProtocolLine::parse(text : String) -> ProtocolLine raise ValueError {
  match text {
    "0.1" => Mep0_1
    "0.2.0-draft.1" => Mep0_2Draft1
    _ => raise UnknownProtocolLine(text)
  }
}

///|
pub impl Show for ProtocolLine with fn output(self, logger) {
  logger.write_string(
    match self {
      Mep0_1 => "0.1"
      Mep0_2Draft1 => "0.2.0-draft.1"
    },
  )
}

///|
pub extend ProtocolLine with Show::{to_string, output}

///|
/// The closed set of MEP operations. `Compile` and `Generate` belong to MEP
/// 0.1; the model operations belong to MEP 0.2.0-draft.1.
pub(all) enum Operation {
  Compile
  Generate
  CompileModel
  GenerateModel
} derive(Eq, Debug)

///|
pub extend Operation with Eq::{equal, not_equal}

///|
pub extend Operation with @debug.Debug::{to_repr}

///|
pub fn Operation::parse(text : String) -> Operation raise ValueError {
  match text {
    "morphir.frontend.compile" => Compile
    "morphir.backend.generate" => Generate
    "morphir.frontend.compileModel" => CompileModel
    "morphir.backend.generateModel" => GenerateModel
    _ => raise UnknownOperation(text)
  }
}

///|
pub fn Operation::protocol_line(self : Operation) -> ProtocolLine {
  match self {
    Compile | Generate => Mep0_1
    CompileModel | GenerateModel => Mep0_2Draft1
  }
}

///|
pub fn Operation::model(self : Operation) -> ModelOperation? {
  match self {
    Compile | Generate => None
    CompileModel => Some(CompileModel)
    GenerateModel => Some(GenerateModel)
  }
}

///|
pub impl Show for Operation with fn output(self, logger) {
  logger.write_string(
    match self {
      Compile => "morphir.frontend.compile"
      Generate => "morphir.backend.generate"
      CompileModel => "morphir.frontend.compileModel"
      GenerateModel => "morphir.backend.generateModel"
    },
  )
}

///|
pub extend Operation with Show::{to_string, output}

///|
/// A model operation: the only operations a model tuple can carry.
pub(all) enum ModelOperation {
  CompileModel
  GenerateModel
} derive(Eq, Debug)

///|
pub extend ModelOperation with Eq::{equal, not_equal}

///|
pub extend ModelOperation with @debug.Debug::{to_repr}

///|
pub fn ModelOperation::operation(self : ModelOperation) -> Operation {
  match self {
    CompileModel => CompileModel
    GenerateModel => GenerateModel
  }
}

///|
pub impl Show for ModelOperation with fn output(self, logger) {
  self.operation().output(logger)
}

///|
pub extend ModelOperation with Show::{to_string, output}

///|
pub(all) enum ModelProfile {
  MorphirModel
  MorphirIr
} derive(Eq, Debug)

///|
pub extend ModelProfile with Eq::{equal, not_equal}

///|
pub extend ModelProfile with @debug.Debug::{to_repr}

///|
pub impl Show for ModelProfile with fn output(self, logger) {
  logger.write_string(
    match self {
      MorphirModel => "morphir-model"
      MorphirIr => "morphir-ir"
    },
  )
}

///|
pub extend ModelProfile with Show::{to_string, output}

///|
pub(all) enum ModelCodec {
  IonBinary
  MorphirJson
} derive(Eq, Debug)

///|
pub extend ModelCodec with Eq::{equal, not_equal}

///|
pub extend ModelCodec with @debug.Debug::{to_repr}

///|
pub impl Show for ModelCodec with fn output(self, logger) {
  logger.write_string(
    match self {
      IonBinary => "ion-binary"
      MorphirJson => "morphir-json"
    },
  )
}

///|
pub extend ModelCodec with Show::{to_string, output}

///|
pub(all) enum EnvelopeVersion {
  V0_1_0Draft1
} derive(Eq, Debug)

///|
pub extend EnvelopeVersion with Eq::{equal, not_equal}

///|
pub extend EnvelopeVersion with @debug.Debug::{to_repr}

///|
pub impl Show for EnvelopeVersion with fn output(self, logger) {
  logger.write_string(
    match self {
      V0_1_0Draft1 => "0.1.0-draft.1"
    },
  )
}

///|
pub extend EnvelopeVersion with Show::{to_string, output}

///|
pub(all) enum IrVersion {
  V4_0_0
} derive(Eq, Debug)

///|
pub extend IrVersion with Eq::{equal, not_equal}

///|
pub extend IrVersion with @debug.Debug::{to_repr}

///|
pub impl Show for IrVersion with fn output(self, logger) {
  logger.write_string(
    match self {
      V4_0_0 => "4.0.0"
    },
  )
}

///|
pub extend IrVersion with Show::{to_string, output}

///|
/// The one five-part tuple the host offers for a model method. The worker
/// must return it unchanged.
pub struct ModelTuple {
  operation : ModelOperation
  profile : ModelProfile
  codec : ModelCodec
  envelope_version : EnvelopeVersion
  ir_version : IrVersion
} derive(Eq, Debug)

///|
pub extend ModelTuple with Eq::{equal, not_equal}

///|
pub extend ModelTuple with @debug.Debug::{to_repr}

///|
pub fn ModelTuple::new(
  operation : ModelOperation,
  profile : ModelProfile,
  codec : ModelCodec,
  envelope_version : EnvelopeVersion,
  ir_version : IrVersion,
) -> ModelTuple {
  { operation, profile, codec, envelope_version, ir_version, }
}

///|
fn[T : Show] closed_part(
  values : Array[T],
  text : String,
) -> T raise ValueError {
  match values.search_by(value => value.to_string() == text) {
    Some(index) => values[index]
    None => raise UnknownModelTuplePart(text)
  }
}

///|
/// Decodes the five wire strings of a tuple. A part outside the closed set is
/// refused rather than passed through.
pub fn ModelTuple::parse(
  operation : String,
  profile : String,
  codec : String,
  envelope_version : String,
  ir_version : String,
) -> ModelTuple raise ValueError {
  {
    operation: closed_part([CompileModel, GenerateModel], operation),
    profile: closed_part([MorphirModel, MorphirIr], profile),
    codec: closed_part([IonBinary, MorphirJson], codec),
    envelope_version: closed_part([V0_1_0Draft1], envelope_version),
    ir_version: closed_part([V4_0_0], ir_version),
  }
}
