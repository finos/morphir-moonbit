///|
pub(all) struct JSONRewrite {
  content : String
  lineage : @data.Lineage?
}

///|
pub(all) enum Component {
  Native((@ir.IRFile) -> @data.Rewrite raise)
  JSON((String) -> JSONRewrite raise)
}

///|
priv struct ComponentStep {
  name : String
  component : Component
  policy_name : String
  policy : @data.MetadataPolicy
}

///|
pub(all) struct ComponentBoundary {
  name : String
  transport : String
  metadata_policy : String
}

///|
pub fn Engine::register_component(
  self : Engine,
  name : String,
  component : Component,
) -> Unit raise {
  if name == "" || self.components.contains(name) {
    raise @configuration.Invalid("component.registration_conflict: " + name)
  }
  self.components[name] = component
}

///|
pub fn Engine::register_metadata_policy(
  self : Engine,
  name : String,
  policy : @data.MetadataPolicy,
) -> Unit raise {
  if name == "" || self.metadata_policies.contains(name) {
    raise @configuration.Invalid("component.policy_conflict: " + name)
  }
  self.metadata_policies[name] = policy
}

///|
fn apply_component(
  unit : @data.IRUnit,
  step : ComponentStep,
) -> @data.IRUnit raise {
  let rewrite = match step.component {
    Native(run) => run(unit.distribution)
    JSON(run) => {
      let result = run(@data.semantic_json(unit))
      { distribution: @ir_json.read(result.content), lineage: result.lineage, }
    }
  }
  @data.apply_rewrite(unit, rewrite, step.name, step.policy_name, step.policy)
}

///|
pub fn Plan::component_boundaries(self : Plan) -> Array[ComponentBoundary] {
  let result = []
  for job in self.jobs {
    for step in job.components {
      result.push({
        name: step.name,
        transport: match step.component {
          Native(_) => "native-ir"
          JSON(_) => "morphir-json"
        },
        metadata_policy: step.policy_name,
      })
    }
  }
  result
}
