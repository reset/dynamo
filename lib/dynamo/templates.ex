defrecord Dynamo.Template, key: nil, identifier: nil, format: nil,
    handler: nil, updated_at: nil, extra: nil, ref: nil, finder: nil do
  @moduledoc """
  The template record is responsible to keep information about
  templates to be rendered. It contains:

  * `:key` - The key used to find the template;
  * `:identifier` - An unique identifier for the template, like its
     filesystem path. This information may be used later by the finder
     to retrieve the template source
  * `:format` - The template format
  * `:finder` - The finder that found the template
  * `:handler` - The handler responsible for compiling the template
  * `:updated_at` - The last time the template was updated
  * `:extra` - Used by the finder to put extra information about the template

  Besides, the followig fields are private to Dynamo:

  * `:ref` - A reference for already compiled templates
  """
end

defexception Dynamo.TemplateNotFound, query: nil, paths: nil do
  def message(exception) do
    "Could not find template #{inspect exception.query} in any of the paths: #{inspect exception.paths}"
  end
end

defmodule Dynamo.Templates do
  @doc """
  Finds the given template in any of the templates paths.
  """
  def find(query, _tmpl_paths) when is_record(query, Template) do
    query
  end

  def find(query, tmpl_paths) do
    Enum.find_value(tmpl_paths, Dynamo.Templates.Finder.find(&1, query))
  end

  @doc """
  Finds the given template in any of the templates paths,
  raises `Dynamo.TemplateNotfound` if a template cannot be found.
  """
  def find!(query, tmpl_paths) do
    find(query, tmpl_paths) ||
      raise Dynamo.TemplateNotFound, query: query, paths: tmpl_paths
  end

  @doc """
  Renders the given template with the given assigns.
  """
  def render(template, locals, assigns, prelude) do
    Dynamo.Templates.Renderer.render(template, locals, assigns, prelude)
  end

  @doc """
  Compiles the given set of `templates` into a module
  given by `name`. It returns the module binary,
  """
  def compile_module(name, templates, locals, prelude) do
    { finders, _ } =
      Enum.map_reduce templates, 0, fn(Dynamo.Template[] = template, i) ->
        template = template.ref({ name, :"template_#{i}" })
        finder   = quote do
          def find(unquote(template.key)) do
            unquote(Macro.escape(template))
          end
        end
        { finder, i + 1 }
      end

    { templates, _ } =
      Enum.map_reduce templates, 0, fn(Dynamo.Template[] = template, i) ->
        source = Dynamo.Templates.Finder.source(template.finder, template)
        { args, source } = template.handler.compile(template, source, locals)

        template =
          quote do
            @file unquote(template.identifier)
            def unquote(:"template_#{i}")(unquote_splicing(args)) do
              unquote(source)
            end
          end
        { template, i + 1 }
      end

    contents =
      quote do
        unquote(prelude.())
        unquote(templates)
        unquote(finders)

        def find(_) do
          nil
        end

        def all do
          nil
        end

        def precompiled? do
          true
        end
      end

    { :module, _, binary, _ } = Module.create(name, contents, file: "(#{inspect name})")
    binary
  end
end