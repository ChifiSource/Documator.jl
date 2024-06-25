<div align="center" style = "box-pack: start;">
  </br>
  <img width = 300 src="https://github.com/ChifiSource/image_dump/blob/main/documentor/logo.png" >
  
  
  [![version](https://juliahub.com/docs/Lathe/version.svg)](https://juliahub.com/ui/Packages/Lathe/6rMNJ)
[![deps](https://juliahub.com/docs/Lathe/deps.svg)](https://juliahub.com/ui/Packages/Lathe/6rMNJ?t=2)
[![pkgeval](https://juliahub.com/docs/Lathe/pkgeval.svg)](https://juliahub.com/ui/Packages/Lathe/6rMNJ)
  </br>
  </br>
  <h1>Documator.jl</h1>
  </div>
  
Documator is an automatic, active-webserver documentation deployment solution for julia. This application builds automatic documentation referencing, searching, and special component interpolation -- all built on the back of the `Toolips` web-development framework. 
### adding
Step one is adding the package. This package will be a dependency of a project which contains all of your documentation, so we start by creating a new environment. Let's say that we wanted to document [`Toolips`](https://github.com/ChifiSource/Toolips.jl) and `ToolipsServables` in from the `toolips` ecosystem. We would add documator, plus both of those packages.
```julia
julia> ]
pkg> generate TLDocServer
pkg> activate TLDocServer
pkg> add Toolips
pkg> add ToolipsServables
pkg> add Documator
```
### setup
After we have an environment with the modules we want to build for loaded, we will first want to call `Documator.generate(groups::Pair{String, Vector{Module}} ...)`. This allows us to group our modules according to ecosystem. This will a `config.toml` alongside a bunch of directories for our project. From here on, we are able to call `generate(...` in this same directory to add additional documentation. After this, we simply need to provide our `Module` to `read_doc_config` before calling `start!` on documator. 
```julia
function start_project(ip::IP4 = "192.168.1.10":8000, path::String = pwd())
    docloader = Documator.docloader
    docloader.dir = path
    docloader.docsystems = Documator.read_doc_config(path, TLDocServer)
    Documator.load_docs!(TLDocServer, docloader)
    start!(Documator, ip)
end
```
From here, we can add `md` to the folders in `modules/` to add more documentation, while a reference and doc interpolation are generated for us.
- A great example of a precreated and deployed, working version of this would be [ChifiDocs](https://github.com/ChifiSource/ChifiDocs.jl)
- A special `components` vector may also be exported from your module to load those components into interpolation for your markdown files.
```julia
module MyDocumatorServer
using Documator
using Documator.Toolips.Components
using ModToDoc

function start_project(ip::IP4 = "192.168.1.10":8000, path::String = pwd())
    docloader = Documator.docloader
    docloader.dir = path
    docloader.docsystems = Documator.read_doc_config(path, MyDocumatorServer)
    Documator.load_docs!(MyDocumatorServer, docloader)
    start!(Documator, ip)
end

components = []

push!(components, a("sample", text = "this was interpolated"))
export components
end
```
