defmodule WorkflowEx.TypedSchemaHelpers do
  @moduledoc """
  Create `new` and `new!` functions for `typed_embedded_schema` via a `def_new` macro

  ## Rationale

  Ecto changeset functions can be used to create validated structs.  Normally, these functions are largely boilerplate
  and the noise generated make it easy to overlook changes in the defined fields or avoid doing validation
  altogether.

  The `def_new` macro will define `new` and `new!` functions for struct construction and validation.

  The `new` function takes a map of attributes or a struct, does Ecto.cast of all defined fields, validates any required
  fields, and does `Ecto.apply_action` to validate the changeset.  Returning `{:ok, <struct>}` if everything is OK,
  `{:error, <changeset>}` if there were issues with `cast` or validation.  If a struct is passed to the `new` function,
  it will be converted to a map

  The `new!` function calls `new` and returns the struct if successful, and raises if not

  ## Macro options

  The `def_new` macro accepts a Keyword options list to control default values and required fields

  - `required:` - an atom or list of atoms for the fields that are required.  The special atom of `:all` indicates that
      all defined fields are required, whereas the atom `:none` disables required field validation
  - `not_required:` - an atom or list of atoms specifying which fields, of all defined, that are not required.
  - `default:` - a tuple or list of tuples of the form `{:field, MFA-tuple}` or `{:field, <constant value>} that
      specify default values for fields missing in the provided attributes map.

  ## Examples

  ```elixir
  typed_embedded_schema do
    field(:uuid, Ecto.UUID)
    field(:event, Belay.Ecto.Any)
    field(:event_array, {:array, Belay.Ecto.Any})
    field(:qty, :decimal)
  end
  ```

  def_new(not_required: [:uuid, :event, :event_array])
  def_new(required: :all)
  def_new(required: :none)
  def_new(required: [:qty])
  def_new(required: :qty)
  def_new(required: :qty, default: [{:uuid, {Ecto.UUID, :generate, []}}, {:event, :before}])
  """
  import Ecto.Changeset

  defmacro __using__(_opts) do
    quote location: :keep do
      use TypedEctoSchema
      import Ecto.Changeset
      import unquote(__MODULE__)

      @primary_key false
    end
  end

  # credo:disable-for-next-line
  defmacro def_new(opts \\ []) do
    quote do
      # if `@req_attrs` already specified then don't override
      unless Module.has_attribute?(__MODULE__, :req_attrs) do
        Module.register_attribute(__MODULE__, :req_attrs, accumulate: false)

        # `required:` - declarative set of fields that are required, if `:all` then all declared fields are required
        # `not_required:` - set of declared fields that are NOT required
        cond do
          required = Keyword.get(unquote(opts), :required) ->
            Module.put_attribute(__MODULE__, :req_attrs, {:required, required})

          not_required = Keyword.get(unquote(opts), :not_required) ->
            Module.put_attribute(__MODULE__, :req_attrs, {:not_required, not_required})

          true ->
            nil
        end
      end

      # accept a list of field default specifiers of form: `{field, <mfa-tuple>}`
      Module.register_attribute(__MODULE__, :default_fields, accumulate: false)
      Module.put_attribute(__MODULE__, :default_fields, Keyword.get(unquote(opts), :default, []))

      @spec new(map() | struct()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
      def new(attrs) when is_struct(attrs) do
        attrs
        |> Map.from_struct()
        |> new()
      end

      def new(attrs) do
        cast_fields =
          __MODULE__.__schema__(:fields)
          |> Kernel.++(__MODULE__.__schema__(:virtual_fields))
          |> Enum.reject(&(&1 in __MODULE__.__schema__(:embeds)))

        attrs = default_fields(attrs, @default_fields)

        %__MODULE__{}
        |> change(attrs)
        |> default_fields(@default_fields)
        |> cast(attrs, cast_fields)
        |> maybe_cast_embeds(attrs)
        |> do_required(
          @req_attrs,
          __MODULE__.__schema__(:fields) ++ __MODULE__.__schema__(:virtual_fields)
        )
        |> apply_action(:new)
      end

      @spec new!(map() | struct()) :: t()
      def new!(attrs) do
        case new(attrs) do
          {:ok, val} -> val
          {:error, cs} -> raise "Invalid #{__MODULE__}.new!(): #{inspect(cs.errors)}"
        end
      end

      def maybe_cast_embeds(changeset, attrs) do
        case __MODULE__.__schema__(:embeds) do
          [] ->
            changeset

          embeds ->
            Enum.reduce(embeds, changeset, fn field, changeset -> cast_embed(changeset, field) end)
        end
      end
    end
  end

  def default_fields(attrs, default_fields) do
    # params =
    List.wrap(default_fields)
    |> Enum.reduce(attrs, fn
      {field, {m, f, a}}, attrs -> Map.put_new(attrs, field, apply(m, f, a))
      {field, value}, attrs -> Map.put_new(attrs, field, value)
    end)

    # cast(struct, params, Map.keys(params))
  end

  def do_required(changeset, {:required, :none}, _all_fields), do: changeset

  def do_required(changeset, {:required, :all}, all_fields),
    do: validate_required(changeset, all_fields)

  def do_required(changeset, {:required, fields}, _all_fields),
    do: validate_required(changeset, fields)

  def do_required(changeset, {:not_required, fields}, all),
    do: validate_required(changeset, all -- List.wrap(fields))

  def do_required(changeset, req_attrs, _all), do: validate_required(changeset, req_attrs)
end
