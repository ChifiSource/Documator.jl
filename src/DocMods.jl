abstract type DocServable end

mutable struct DocModule <: DocServable
    name::String
    color::String
    pages::Vector{Component{<:Any}}
    projectpath::String
    docstrings::Vector{Component{<:Any}}
    DocModule(name::String, color::String, pag::Vector, path::String) = new(name, 
    color, pag, path, Vector{Component{<:Any}}())
end

mutable struct DocSystem <: DocServable
    name::String
    modules::Vector{DocModule}
    ecodata::Dict{String, Any}
end

getindex(dc::Vector{<:DocServable}, ref::AbstractString) = begin
    pos = findfirst(cl::DocServable -> cl.name == ref, dc)
    if isnothing(pos)
        throw("$ref was not in here")
    end
    dc[pos]::DocServable
end

mutable struct ClientDocLoader <: Toolips.AbstractExtension
    dir::String
    docsystems::Vector{DocSystem}
    pages::Vector{AbstractComponent}
    menus::Vector{AbstractComponent}
    components::Vector{AbstractComponent}
    homename::String
    routes::Vector{Toolips.Route{Connection}}
    ClientDocLoader(docsystems::Vector{DocSystem} = Vector{DocSystem}()) = begin
        pages::Vector{AbstractComponent} = Vector{AbstractComponent}()
        new("", docsystems, pages, 
        Vector{AbstractComponent}(), Vector{AbstractComponent}(), "", 
        Vector{Toolips.Route{Connection}}())::ClientDocLoader
    end
end

docloader = ClientDocLoader()

function read_doc_config(path::String, mod::Module = Main)
    data = TOML.parse(read(path * "/config.toml", String))
    docsystems::Vector{DocSystem} = Vector{DocSystem}()
    homepage = ""
    for ecosystem in data
        if ecosystem[1] == "home"
            homepage = ecosystem[2]
            continue
        end
        ecodata = ecosystem[2]
        name = ecosystem[1]
        mods = reverse(Vector{DocModule}(filter(k -> ~(isnothing(k)), [begin
            docmod_from_data(dct[1], dct[2], mod, path)
        end for dct in filter(k -> typeof(k[2]) <: AbstractDict, ecodata)])))
        push!(docsystems, 
        DocSystem(name, mods, Dict{String, Any}(ecodata)))
    end
    if homepage == ""
        homepage = docsystems[1].modules[1]
    end
    return(reverse(docsystems), homepage)
end

JULIA_HIGHLIGHTER = OliveHighlighters.TextStyleModifier()
OliveHighlighters.julia_block!(JULIA_HIGHLIGHTER)
style!(JULIA_HIGHLIGHTER, :default, ["color" => "white"])
style!(JULIA_HIGHLIGHTER, :funcn, ["color" => "lightblue"])
style!(JULIA_HIGHLIGHTER, :params, ["color" => "#D2B48C"])

function julia_interpolator(raw::String)
    tm = JULIA_HIGHLIGHTER
    set_text!(tm, raw)
    OliveHighlighters.mark_julia!(tm)
    ret::String = string(tm)
    OliveHighlighters.clear!(tm)
    jl_container = div("jlcont", text = ret)
    style!(jl_container, "background-color" => "#1e1e1e", "font-size" => 10pt, "padding" => 25px, 
    "margin" => 25px, "overflow" => "auto", "max-height" => 25percent, "border-radius" => 3px)
    string(jl_container)::String
end

function docstring_interpolator(raw::String)
    docnames = split(raw, "\n")
    ret::String = ""
    for name in docnames
        found = findfirst(c -> c.name == "$name-md", docloader.pages)
        if isnothing(found)
            @warn "unable to find quoted docstring: $name"
            continue
        end
        container = div("container-$name")
        style!(container, "background-color" => "#F5F5F5", "border-radius" => 8px, "border" => "2px solid #333333", 
        "padding" => 25px, "margin" => 25px, "text-wrap" => "wrap", "flex-wrap" => "wrap", "font-size" => 12pt)
        cop = docloader.pages["$name-md"]
        style!(cop, "position" => "relative")
        push!(container, h2(text = "$name docs"), cop)
        ret =  ret * string(container)
    end
    ret::String
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
    path::String = path * "/modules/" * dct_data["path"]
    @info "|- - - $path"
    pages = [begin
        pagen = split(n, "_")[2]
        # (cut off .md)
        pagen = pagen[1:length(pagen) - 3]
        rawsrc::String = replace(read(path * "/" * n, String), "\"" => "\\|", "<" => "|\\", ">" => "||\\")
        newmd = tmd(replace(pagen, " " => "-"), rawsrc)
        newmd[:text] = replace(Components.rep_in(newmd[:text]), "\\|" => "\"", "|\\" => "<", "||\\" => ">", "&#33;" => "!", "â€”" => "--", "&#61;" => "=", 
        "&#39;" => "'", "&#91;" => "[", "&#123;" => "{", "&#93;" => "]")
        newmd
    end for n in readdir(path)]
    DocModule(name, dct_data["color"], pages, path)
end

function generate(groups::Pair{String, Vector{Module}} ...)

end