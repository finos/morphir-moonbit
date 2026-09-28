// Based on finos/morphir's v4 semantic model and schema.
// Copyright 2026 FINOS. SPDX-License-Identifier: Apache-2.0

///|
pub(all) struct SourceLocation {
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
} derive(Eq, Debug)

///|
pub(all) struct TypeAttributes {
  source : SourceLocation?
  constraints : Map[String, Data]
  extensions : Map[String, Data]
} derive(Eq, Debug, Default)

///|
pub(all) struct ValueAttributes {
  source : SourceLocation?
  inferred_type : Type?
  extensions : Map[String, Data]
} derive(Eq, Debug, Default)

///|
pub(all) enum Type {
  Variable(TypeAttributes, Name)
  Reference(TypeAttributes, FQName, Array[Type])
  Tuple(TypeAttributes, Array[Type])
  Record(TypeAttributes, Map[Name, Type])
  ExtensibleRecord(TypeAttributes, Name, Map[Name, Type])
  Function(TypeAttributes, Type, Type)
  Unit(TypeAttributes)
} derive(Eq, Debug)

///|
pub type Constructors = Map[Name, Array[(Name, Type)]]

///|
pub(all) enum Annotation {
  Compact(FQName, String?)
  Structured(FQName, Array[AnnotationArgument])
} derive(Eq, Debug)

///|
pub(all) enum AnnotationArgument {
  Positional(Value)
  Named(Name, Value)
} derive(Eq, Debug)

///|
pub(all) struct TypeSpecification {
  annotations : Array[Annotation]
  body : TypeSpecificationBody
} derive(Eq, Debug)

///|
pub(all) enum TypeSpecificationBody {
  TypeAliasSpecification(Array[Name], Type)
  OpaqueTypeSpecification(Array[Name])
  CustomTypeSpecification(Array[Name], Constructors)
  DerivedTypeSpecification(Array[Name], DerivedTypeDetails)
} derive(Eq, Debug)

///|
pub(all) struct DerivedTypeDetails {
  base_type : Type
  from_base_type : FQName
  to_base_type : FQName
} derive(Eq, Debug)

///|
pub(all) enum TypeDefinition {
  TypeAliasDefinition(Array[Name], Type)
  CustomTypeDefinition(Array[Name], AccessControlled[Constructors])
  IncompleteTypeDefinition(Array[Name], Incompleteness, Type?)
} derive(Eq, Debug)

///|
pub(all) enum HoleReason {
  UnresolvedReference(FQName)
  DeletedDuringRefactor(String)
  TypeMismatch(String, String)
} derive(Eq, Debug)

///|
pub(all) enum Incompleteness {
  Hole(HoleReason, Type?)
  Draft
} derive(Eq, Debug)
