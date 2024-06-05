abstract type DocServable end

mutable struct DocModule <: DocServable
    name::String
    color::String
    pages::Vector{Component{<:Any}}
    projectpath::String
end

mutable struct DocSystem <: DocServable
    name::String
    modules::Vector{DocModule}
    ecodata::Dict{String, Any}
end

getindex(dc::Vector{<:DocServable}, ref::String) = begin
    pos = findfirst(cl::DocServable -> cl.name == ref, dc)
    if isnothing(pos)
        throw("$ref was not in here")
    end
    dc[pos]::DocServable
end

abstract type AbstractDocClient end

mutable struct DocClient <: AbstractDocClient
    key::String
    tabs::Vector{Component{<:Any}}
end

getindex(dc::Vector{<:AbstractDocClient}, ref::String) = begin
    pos = findfirst(cl::AbstractDocClient -> cl.key == ref, dc)
    if isnothing(pos)

    end
    dc[pos]::AbstractDocClient
end

function read_doc_config(path::String, mod::Module = Main)
    data = TOML.parse(read(path, String))
    docsystems::Vector{DocSystem} = Vector{DocSystem}()
    for ecosystem in data
        ecodata = ecosystem[2]
        name = ecosystem[1]
        mods = reverse(Vector{DocModule}(filter(k -> ~(isnothing(k)), [begin
            docmod_from_data(dct[1], dct[2], mod, path)
        end for dct in filter(k -> typeof(k[2]) <: AbstractDict, ecodata)])))
        push!(docsystems, 
        DocSystem(name, mods, Dict{String, Any}(ecodata)))
    end
    reverse(docsystems)::Vector{DocSystem}
end

JULIA_HIGHLIGHTER = OliveHighlighters.TextStyleModifier()
OliveHighlighters.julia_block!(JULIA_HIGHLIGHTER)

function julia_interpolator(raw::String)
    tm = JULIA_HIGHLIGHTER
    set_text!(tm, raw)
    OliveHighlighters.mark_julia!(tm)
    string(tm)::String
end

html_interpolator(raw::String) = OliveHighlighters.rep_in(raw)::String

function img_interpolator(raw::String)
    if contains(raw, "|")
        splits = split(raw, "|")
        if length(splits) == 3
            return(string(div(Components.gen_ref(3), align = splits[2], 
            children = [img(Components.gen_ref(3), src = splits[3], width = splits[1])])))::String
        end
        return(string(img(Components.gen_ref(3), src = splits[2], width = splits[1])))::String
    end
    string(img(Components.gen_ref(3), src = raw))::String
end

function docmod_from_data(name::String, dct_data::Dict{String, <:Any}, mod::Module, path::String)
    data_keys = keys(dct_data)
    if ~("color" in data_keys)
        push!(dct_data, "color" => "lightgray")
    end
    if ~("path" in data_keys)
        @warn "$name has no path, skipping"
        return(nothing)::Nothing
    end
    pages = Vector{Component{<:Any}}()
    this_docmod::Module = getfield(mod, Symbol(name))
    docstrings = [begin
        docname = string(sname)
        inline_comp = a(docname, text = docname, class = "inline-doc")
        on(session, docname) do cm::ComponentModifier
            docstring = "no documentation found for $docname :("
            try
                f = getfield(this_docmod, sname)
                docstring = string(this_docmod.eval(Meta.parse("@doc($docname)")))
            catch

            end
            docstr_tmd = tmd("$docname-md", string(docstring))
            docstr_window = div("$docname-window", children = [docstr_tmd])
            cursor = cm["doccursor"]
            xpos, ypos = cursor["x"], cursor["y"]
            style!(docstr_window, "position" => "absolute", "top" => ypos, "left" => xpos, 
            "border-radius" => 4px, "border" => "2px solid #333333", "background-color" => "white")
            append!(cm, "main", docstr_window)
        end
        on(docname, inline_comp, "click")
        inline_comp
    end for sname in names(this_docmod)]
    path::String = split(path, "/")[1] * "/modules/" * dct_data["path"]
    if "pages" in data_keys
        dpages = dct_data["pages"]
        pages = [begin
            rawsrc::String = replace(read(path * "/" * dpages[n], String), "\"" => "\\|", "<" => "|\\", ">" => "||\\")
            newmd = tmd(string(dpages[n - 1]), rawsrc)
            newmd[:text] = replace(newmd[:text], "\\|" => "\"", "|\\" => "<", "||\\" => ">")
            ToolipsServables.interpolate!(newmd, "julia" => julia_interpolator, "img" => img_interpolator, 
            "html" => html_interpolator)
            ToolipsServables.interpolate!(newmd, docstrings ...)
            newmd
        end for n in range(2, length(dpages), step = 2)]
    end
    DocModule(name, dct_data["color"], 
        pages, path)
end