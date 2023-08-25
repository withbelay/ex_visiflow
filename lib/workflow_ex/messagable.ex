defprotocol WorkflowEx.Messagable do
  def send_message(state, message)
end
