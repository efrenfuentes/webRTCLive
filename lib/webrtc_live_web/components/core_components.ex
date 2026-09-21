defmodule WebRTCLiveWeb.CoreComponents do
  use Phoenix.Component

  slot(:inner_block, required: true)
  slot(:subtitle)

  def header(assigns) do
    ~H"""
    <header><h1>{render_slot(@inner_block)}</h1><p :for={subtitle <- @subtitle}>{render_slot(subtitle)}</p></header>
    """
  end

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:type, :string, default: "text")
  attr(:label, :string, default: nil)
  attr(:rest, :global, include: ~w(readonly autocomplete spellcheck required))

  def input(assigns) do
    ~H"""
    <label for={@field.id}>{@label}</label>
    <input id={@field.id} name={@field.name} type={@type} value={Phoenix.HTML.Form.normalize_value(@type, @field.value)} {@rest} />
    <p :for={error <- @field.errors} role="alert">{error_message(error)}</p>
    """
  end

  defp error_message({message, options}) do
    Enum.reduce(options, message, fn {key, value}, text ->
      String.replace(text, "%{#{key}}", to_string(value))
    end)
  end

  attr(:variant, :string, default: nil)
  attr(:rest, :global, include: ~w(name value type disabled))
  slot(:inner_block, required: true)

  def button(assigns) do
    ~H"""
    <button {@rest}>{render_slot(@inner_block)}</button>
    """
  end

  attr(:name, :string, required: true)
  attr(:rest, :global)

  def icon(assigns) do
    ~H"""
    <span aria-hidden="true" {@rest}>ⓘ</span>
    """
  end
end
