module Documator
using Toolips
using TOML
using Toolips.Components
import Toolips.Components: AbstractComponentModifier
import Toolips: on_start, route!
import Base: getindex
using ToolipsSession
using OliveHighlighters

# extensions
logger = Toolips.Logger()
session = Session(Vector{String}(), invert_active = true)

include("DocMods.jl")

function on_start(ext::ClientDocLoader, data::Dict{Symbol, Any}, routes::Vector{<:AbstractRoute})
    ss = make_stylesheet()
    DOCROUTER.file_routes = mount("/" => "$(ext.dir)/public")
    for r in DOCROUTER.file_routes
        push!(session.active_routes, r.path)
    end
    push!(ext.pages, ss, generate_menu(ext.docsystems))
    push!(data, :doc => ext)
    compress_pages!(ext)
end

function compress_pages!(ext::ClientDocLoader)
    @info "COMPRESSING ..."
    GC.gc(true)
end

function build_docstrings(mod::Module, docm::DocModule)
    hover_docs = Vector{Toolips.AbstractComponent}()
    ativ_mod = mod.eval(Meta.parse(docm.name))
    docstrings = [begin
        docname = replace(string(sname), "#" => "")
        # make doc-string
        docstring = "no documentation found for $docname :("
        try
            docstring = string(ativ_mod.eval(Meta.parse("@doc($docname)")))
        catch
        end
        docstr_tmd = tmd("$docname-md", replace(docstring, "\"" => "\\|", "<" => "|\\", ">" => "||\\"))
        docstr_tmd[:text] = replace(docstr_tmd[:text], "\\|" => "\"", "|\\" => "<", "||\\" => ">", "&#33;" => "!", "â€\"" => "--", "&#61;" => "=", 
        "&#39;" => "'", "&#91;" => "[", "&#123;" => "{", "&#93;" => "]")
        ToolipsServables.interpolate!(docstr_tmd, "julia" => julia_interpolator, "img" => img_interpolator, 
                "html" => html_interpolator, "docstrings" => docstring_interpolator, "example" => julia_interpolator)
        inline_comp = a(docname, text = docname, class = "inline-doc")
        push!(hover_docs, inline_comp)
        on(session, docname) do cm::ComponentModifier
            close_button = button("closedoc", text = "v")
            style!(close_button, "background-color" => "#8a0a25", "color" => "white", 
            "font-weight" => "bold", "padding" => .7percent, "border" => "none", 
            "border-radius" => 6px, "font-size" => 16pt, "cursor" => "pointer")
            on(close_button, "click") do cl::ClientModifier
                remove!(cl, "$docname-window")
            end
            close_container = div("close_container", align = "right", children = [close_button])
            docstr_window = div("$docname-window", children = [close_container, docstr_tmd], align = "left")
            cursor = cm["doccursor"]
            style!(docstr_window, "position" => "absolute", "top" => 3percent, "left" => 20percent,
            "border-radius" => 4px, "border" => "2px solid #333333", "background-color" => "white", "padding" => 15px, 
            "height" => 89.1percent, "width" => 76percent, "overflow-y" => "scroll", "overflow-x" => "wrap")
            append!(cm, "main", docstr_window)
        end
        on(docname, inline_comp, "click")
        docstr_tmd
    end for sname in names(ativ_mod, all = true)]
    return(docstrings, hover_docs)
end

function generate_systempage(system::DocSystem)
    sys_cover = h2(system.name, text = system.name)
    system_container = div(system.name, align = "left", children = Vector{AbstractComponent}([sys_cover]))
    style!(sys_cover, "color" => system.ecodata["color"])
    if haskey(system.ecodata, "description")
        push!(system_container, tmd("sysdesc", system.ecodata["description"]))
    end
    for mod in system.modules
        new_a = a("-", text = mod.name, href = system.name * "/$(mod.name)")
        style!(new_a, "background-color" => mod.color, "padding" => 5px, "border-radius" => 3px, 
        "color" => "white", "font-weight" => "bold", "cursor" => "pointer")
        push!(system_container, new_a)
    end
    system_container
end

function load_docs!(mod::Module, docloader::ClientDocLoader)
    if :components in(names(mod))
        docloader.components = Vector{AbstractComponent}(mod.components)
        @info "loaded components: $(join("$(comp.name)|" for comp in docloader.components))"
    end
    for system in docloader.docsystems
        push!(docloader.pages, generate_systempage(system))
        @info "preloading $(system.name) content ..."
        for docmod in system.modules
            @info "| $(docmod.name)"
            this_docmod::Module = getfield(mod, Symbol(docmod.name))
            docstrings, hoverdocs = build_docstrings(mod, docmod)
            push!(docloader.pages, docstrings ...)
            [begin
                ToolipsServables.interpolate!(page, "julia" => julia_interpolator, "img" => img_interpolator, 
                "html" => html_interpolator, "docstrings" => docstring_interpolator)
                ToolipsServables.interpolate!(page, hoverdocs ..., docloader.components ...)
            end for page in docmod.pages]
            push!(docloader.menus, div(docmod.name, children = build_leftmenu_elements(docmod)))
        end
    end
end

function generate_menu(mods::Vector{DocSystem})
    menuholder::Component{:div} = div("mainmenu", align = "center", class = "mmenuholder", open = "none",
    children = [begin
        modname = menu_mod.name
        mdiv = div("$modname")
        preview_img = img("preview$modname", src = menu_mod.ecodata["icon"], width = 25px)
        style!(preview_img, "display" => "inline-block", "margin-right" => 5px)
        label_a = a("label$modname", text = modname, class = "mainmenulabel")
        style!(mdiv, "background-color" => menu_mod.ecodata["color"], "overflow" => "hidden", 
        "padding-top" => 2px, "transition" => 500ms, "cursor" => "pointer")
        style!(label_a, "color" => menu_mod.ecodata["txtcolor"])
        push!(mdiv, preview_img, label_a)
        mdiv::Component{:div}
    end for menu_mod in mods])
    childs = menuholder[:children]
    style!(childs[1], "border-top-left-radius" => 3px)
    style!(childs[length(childs)], "border-bottom-left-radius" => 3px)
    menuholder::Component{:div}
end

function bind_menu!(c::AbstractConnection, menu::Component{:div})
    [begin # menu children
        selected_system = c[:doc].docsystems[child.name]
        econame::String = child.name
        submenu = [begin # submenu
        docn = docmod.name
        menitem = div("men$docn")
        style!(menitem, "cursor" => "pointer", "border-radius" => 2px, "background-color" => docmod.color, 
        "border-left" => "3px solid $(selected_system.ecodata["color"])")
        doclabel = div("doclabel", text = docn)
        style!(doclabel, "padding" => 3px, "font-size" => 13pt, "color" => "white")
        push!(menitem, doclabel)
        on(menitem, "click") do cl::ClientModifier
            redirect!(cl, "/$(selected_system.name)/$(docmod.name)")
        end
        menitem
    end for docmod in selected_system.modules]
        on(session, "dec$econame") do cm::ComponentModifier
            opened::String = cm["mainmenu"]["open"]
            if opened == econame
                cm["mainmenu"] = "open" => "none"
                remove!(cm, "expandmenu")
                return
            elseif opened != "none"
                remove!(cm, "expandmenu")
            end
            cm["mainmenu"] = "open" => econame
            
            menuel = div("expandmenu", children = submenu)
            append!(cm, econame, menuel)
        end
        on("dec$econame", child, "click")

    end for child in menu[:children]]
end

function make_stylesheet()
    bttons = Style("button", "font-family" => "storycan")
    h1_sty = Style("h1", "color" => "#333333")
    h2_sty = Style("h2", "color" => "#29232e")
    h3_sty = Style("h3", "color" => "#46383c")
    h4_sty = Style("h4", "color" => "darkblue")
    cod_sty = Style("code", "background-color" => "#333333", "padding" => 1.5px, "border-radius" => 1px, "color" => "white", 
    "font-size" => 10pt)
    jl_cod_sty = Style("code.language-julia", "background-color" => "#333333", "padding" => 10px, "border-radius" => 1px, "font-size" => 10pt, 
    "text-wrap" => "wrap", "overflow-x" => "scroll")
    p_sty = Style("p", "color" => "#191922", "font-size" => 12pt, "font-family" => "lectus")
    lect_font = Style("@font-face", "font-family" => "'lectus'", "src" => "url(/fonts/mreg.ttf)")
    ico_font = Style("@font-face", "font-family" => "'storycan'", "src" => "url(/fonts/storycan-icons.ttf)")
    inldoc = Style("a.inline-doc", "color" => "darkblue", "font-weight" => "bold", 
    "font-size" => 13pt, "cursor" => "pointer", "transition" => 400ms)
    inldoc:"hover":["scale" => "1.07", "color" => "lightblue"]
    tab_x = ("font-size" => 14pt, "border-radius" => 3px, "padding" => 4px, "margin-left" => 10px)
    tab_x_active = Style("a.tabxactive", "color" => "white", "background-color" => "darkred", "font-family" => "storycan",
    "cursor" => "pointer", tab_x ...)
    tab_x_inactive = Style("a.tabxinactive", "color" => "#333333", "background-color" => "lightgray", "font-family" => "storycan",
     "padding" => 9px, tab_x ...)
    left_menu_elements = Style("div.menuitem", "padding" => 8px, "cursor" => "pointer", "overflow" => "visible")
    main_menus = Style("a.mainmenulabel", "font-size" => 18pt, "font-weight" => "bold", 
    "display" => "inline-block", "opacity" => 100percent, "transition" => 400ms)
    menu_holder = Style("div.mmenuholder", "z-index" => 2, "transition" => 800ms,"overflow" => "hidden")
    scrtrack = Style("::-webkit-scrollbar-track", "background" => "transparent")
    scrthumb = Style("::-webkit-scrollbar-thumb", "background" => "pink",
    "border-radius" => "5px")
    topbutton = Style("a.topbutton", "padding" => .5percent, "background-color" => "#1e1e1e", "color" => "white", 
    "font-weight" => "bold", "border-left" => "2px solid white", "cursor" => "pointer", 
    "width" => 10percent, "transition" => 750ms, "padding-top" => .5percent)
    topbutton:"hover":["border-bottom" => "3px solid orange", "font-size" => 14pt]
    sheet = Component{:stylesheet}("styles")
    sheet[:children] = Vector{AbstractComponent}([left_menu_elements, main_menus, 
    menu_holder, ico_font, bttons, inldoc, h1_sty, h2_sty, h3_sty, h4_sty, p_sty, cod_sty, 
    lect_font, scrtrack, scrthumb, topbutton])
    compress!(sheet)
    sheet::Component{:stylesheet}
end


function build_main(c::AbstractConnection, docname::String)
    main_window = div("main_window", align = "left")
    push!(main_window, get_docpage(c, docname))
    style!(main_window, "background-color" => "white", "padding" => 2percent, "border-left" => "2px soid #211f1f", 
    "display" => "block", "overflow-y" => "scroll", "text-wrap" => "wrap", "overflow-x" => "wrap", "width" => 76percent,
    "position" => "absolute", "top" => 3.15percent, "left" => 20percent, "height" => 89.1percent)
    main_window::Component{:div}
end

function build_topbar(c::AbstractConnection, docname::String)
    top_buttons = Vector{AbstractComponent}()
    top_butt = a(text = "home", href = "/", class = "topbutton", align = "center")
    push!(top_buttons, top_butt)
    if docname != docloader.homename
        docn_splits = split(docname, "/")
        top_butt = a(text = docn_splits[1], href = "/" * docn_splits[1], class = "topbutton", align = "center")
        push!(top_buttons, top_butt)
        if length(docn_splits) > 1
            top_butt = a(text = docn_splits[2], href = "/" * docn_splits[1] * "/" * docn_splits[2], class = "topbutton", align = "center")
            push!(top_buttons, top_butt)
        end
    end
    topbar = div("topbar", children = top_buttons, align = "left")
    style!(topbar, "width" => 80percent, "height" => 3percent, "left" => 19.91percent, "background-color" => "#1e1e1e", 
    "position" => "absolute", "top" => 0percent, "display" => "inline-flex")
    topbar
end

function get_docpage(c::AbstractConnection, name::String)
    ecopage::Vector{SubString} = split(name, "/")
    n = length(ecopage)
    if n == 1
        return(div("$name", children = c[:doc].pages[name]))
    elseif n == 2
        return(div("$name", children = c[:doc].docsystems[string(ecopage[1])].modules[string(ecopage[2])].pages))
    end
    c[:doc].docsystems[string(ecopage[1])].modules[string(ecopage[3])].pages[string(ecopage[2])]::Component{<:Any}
end

function build_leftmenu(c::AbstractConnection, name::String)
    ecopage = split(name, "/")
    if length(ecopage) == 1
        return(div("-"))
    end
    mod = c[:doc].docsystems[string(ecopage[1])].modules[string(ecopage[length(ecopage)])]
    items = get_left_menu_elements(c, mod)
    main_menu = copy(c[:doc].pages["mainmenu"])
    bind_menu!(c, main_menu)
    item_inner = div("leftmenu_items", children = items)
    style!(item_inner, "overflow" => "visible")
    left_menu::Component{:div} = div("left_menu")
    push!(left_menu, main_menu, item_inner)
    style!(left_menu, "width" => 19.91percent, "background-color" => "white", "border-right" => "2px solid #1e1e1e", "position" => "absolute", "left" => 0percent, "top" => 0percent,
    "height" => 100percent)
    left_menu::Component{:div}
end

function get_left_menu_elements(c::AbstractConnection, name::Pair{String, String})
    c[:doc].menus[name[2]]
end

function get_left_menu_elements(c::AbstractConnection, docmod::DocModule)
    c[:doc].menus[docmod.name]
end

function build_leftmenu_elements(mod::DocModule)
    modcolor::String = mod.color
    [begin 
        pagename = page.name
        pagesrc::String = page[:text]
        headings = Vector{Int64}()
        lvls::Tuple{Char, Char, Char} = ('1', '2', '3')
        pos::Int64 = 1
        headings = Vector{AbstractComponent}()
        e::Int64 = 1
        n = length(pagesrc)
        while true
            if pos > n
                break
            end
            nexth = [findnext("<h1>", pagesrc, pos), findnext("<h2>", pagesrc, pos), 
            findnext("<h3>", pagesrc, pos)]
            filter!(point -> ~(isnothing(point)), nexth)
            if length(nexth) == 0
                break
            end
            nexth = sort(collect(nexth), by=x->x[1])[1]
            nd = maximum(nexth)
            lvl = pagesrc[maximum(nexth) - 1]
            eotext = findnext("</h$lvl", pagesrc, nd)
            if isnothing(eotext)
                pos = maximum(nexth) + 1
                continue
            end
            txt = pagesrc[nd + 1:minimum(eotext) - 1]
            txtlen = length(txt)
            nwcomp = Component{Symbol("h$lvl")}("$pagename-$e", text = txt)
            nwcompsrc = string(nwcomp)
            try
                pagesrc = pagesrc[1:minimum(nexth) - 1] * nwcompsrc * pagesrc[maximum(eotext) + 3:length(pagesrc)]
            catch
                try
                    pagesrc = pagesrc[1:minimum(nexth) - 1] * nwcompsrc * pagesrc[maximum(eotext) + 4:length(pagesrc)]
                catch
                    try
                        pagesrc = pagesrc[1:minimum(nexth) - 2] * nwcompsrc * pagesrc[maximum(eotext) + 3:length(pagesrc)]
                    catch
                        pos = maximum(eotext)
                        continue
                    end
                end
            end
            men = div("page-$pagename-$e", align = "left", class = "menuitem")
            on(session, "$pagename-men-$e") do cm::ComponentModifier
                scroll_to!(cm, nwcomp, align_top = true)
                scroll_to!(cm, "main", (0, 0))
            end
            on("$pagename-men-$e", men, "click")
            pos = nd + (length(nwcompsrc) - txtlen + 1)
            e += 1
            labela = a("label-$pagename", text = txt)
            style!(labela, "font-size" => 13pt, "font-weight" => "bold", "color" => "#333333")
            push!(men, labela)
            style!(men, "background-color" => "white", "border-left" => "$(1 * 2)px solid $(modcolor)")
            push!(headings, men)
        end
        page[:text] = pagesrc
        openbutton = button("open-$pagename", text = "d")
        style!(openbutton, "border" => 0px, "border-radius" => 2px, "font-size" => 17pt, "background" => "transparent", 
        "color" => "#333333")
        labela = a("label-$pagename", text = replace(pagename, "-" => " "))
        style!(labela, "font-size" => 13pt, "font-weight" => "bold", "color" => "#333333")
        pageover = div("pageover", align = "left")
        pagemenu = div("pagemenu-$pagename", align = "left", class = "menuitem")
        submenu = div("submenu", children = headings)
        style!(submenu, "overflow" => "visible")
        style!(pagemenu, "background-color" => modcolor, "border-bottom" => "2px solid #333333")
        push!(pagemenu, labela, openbutton)
        push!(pageover, pagemenu, submenu)
        pageover::Component{:div}
end for page in mod.pages]::Vector{<:AbstractComponent}
end

abstract type AbstractDocRoute <: Toolips.AbstractRoute end

mutable struct DocRoute <: AbstractDocRoute
    file_routes::Vector{Toolips.Route}
    DocRoute() = new(Vector{Toolips.Route}())
end

route!(c::AbstractConnection, rs::Vector{DocRoute}) = begin
    requested_page = get_route(c)
    if contains(requested_page, ".")
        if requested_page in rs[1].file_routes
            route!(c, rs[1].file_routes)
        end
        return
    end
    pages = c[:doc].pages
    write!(c, pages["styles"])
    mainbody::Component{:body} = body("main", align = "center", children = Vector{AbstractComponent}([cursor("doccursor")]))
    style!(mainbody, "background-color" => "#333333", "overflow" => "hidden", "transition" => 1s)
    if requested_page != "/"
        loaded_page = requested_page[2:end]
    else
        loaded_page = docloader.homename
    end
    bar = build_topbar(c, loaded_page)
    left_menu = build_leftmenu(c, loaded_page)
    push!(mainbody, bar, left_menu, build_main(c, loaded_page))
    write!(c, mainbody)
end


DOCROUTER = DocRoute()

"""
```julia
start_from_project
```
yadda yadda, documentation.
"""
function start_from_project(path::String = pwd(), mod::Module = Main; ip::Toolips.IP4 = "127.0.0.1":8000)
    docloader.dir = path
    docloader.docsystems, docloader.homename = read_doc_config(path * "/config.toml", mod)
    load_docs!(mod, docloader)
    start!(Documator, ip)
end

# make sure to export!
export DOCROUTER, logger, session, docloader, start_from_project, style!
end # - module ChifiDocs <3
