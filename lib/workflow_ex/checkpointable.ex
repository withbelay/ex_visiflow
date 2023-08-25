defprotocol WorkflowEx.Checkpointable do
  def save(state)
  def delete_all(state)
end
