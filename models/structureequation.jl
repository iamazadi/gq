import FileIO
import DataFrames
import CSV
using LinearAlgebra
import GLMakie
using Porta


figuresize = (1920, 1080)
segments = 30
basemapsegments = 30
modelname = "structureequation3"
boundary_names = ["Australia", "Japan", "United States of America", "United Kingdom", "Antarctica", "Iran"]
frames_number = 360 * length(boundary_names)
samplename = "United States of America"
indices = Dict()
ratio = 0.9
x̂ = [1.0; 0.0; 0.0]
ŷ = [0.0; 1.0; 0.0]
ẑ = [0.0; 0.0; 1.0]
linewidth = 10.0
arrowsize = GLMakie.Vec3f(0.02, 0.02, 0.04)
eyeposition = normalize([1; 1; 0]) * 2.0
lookat = [0; 0; 0]
up = normalize([0; 1; 1])
totalstages = length(boundary_names)
initialized = [false for _ in 1:totalstages]


"""
    paralleltransport(q, α, θ, segments)

Parallel transport the basis frame at point `q` in the direction angle `α` with distance `θ`,
and smoothness `segments`.
"""
function paralleltransport(q::Quaternion, α::Float64, θ::Float64, segments::Int)
    x¹ = K(1) * q
    x² = K(2) * q
    x³ = K(3) * q
    v = sin(α) * K(1) + cos(α) * K(2)
    θ₀ = θ / segments
    track = [q]
    track1 = [x¹]
    track2 = [x²]
    track3 = [x³]
    for i in 1:segments
        n = exp(v * i * θ₀) * q
        x¹ = normalize(x¹ - dot(x¹, n) * n)
        x² = normalize(x² - dot(x², n) * n)
        x³ = normalize(x³ - dot(x³, n) * n)
        push!(track, n)
        push!(track1, x¹)
        push!(track2, x²)
        push!(track3, x³)
    end
    track, track1, track2, track3
end


makefigure() = GLMakie.Figure(size = figuresize)
fig = GLMakie.with_theme(makefigure, GLMakie.theme_black())
pl = GLMakie.PointLight(GLMakie.Point3f(0), GLMakie.RGBf(0.0862, 0.0862, 0.0862))
al = GLMakie.AmbientLight(GLMakie.RGBf(0.9, 0.9, 0.9))
lscene = GLMakie.LScene(fig[1, 1], show_axis=false, scenekw = (lights = [pl, al], clear=true, backgroundcolor = :white))

colorref = FileIO.load("data/basemap_color1.png")
basemap_color = FileIO.load("data/basemap_mask1.png")
basemap_color2 = FileIO.load("data/basemap_mask11.png")
## Load the Natural Earth data
attributespath = "data/naturalearth/geometry-attributes.csv"
nodespath = "data/naturalearth/geometry-nodes.csv"
countries = loadcountries(attributespath, nodespath)
boundary_nodes = Vector{Vector{Vector{Float64}}}()
for i in eachindex(countries["name"])
    for name in boundary_names
        if countries["name"][i] == name
            push!(boundary_nodes, countries["nodes"][i])
            indices[name] = length(boundary_nodes)
        end
    end
end

θ1 = float(π)
q = τmap(convert_to_geographic([1.0; 0.0; 0.0]))
basemap1 = Basemap(lscene, q, basemapsegments, basemap_color, transparency = true)
basemap2 = Basemap(lscene, G(float(π), q), basemapsegments, basemap_color, transparency = true)

whirls = []
_whirls = []
for i in eachindex(boundary_nodes)
    color = getcolor(boundary_nodes[i], colorref, 0.5)
    _color = getcolor(boundary_nodes[i], colorref, 0.1)
    w = [τmap(boundary_nodes[i][j]) for j in eachindex(boundary_nodes[i])]
    whirl = Whirl(lscene, w, 0.0, θ1, segments, color, transparency = true)
    _whirl = Whirl(lscene, w, θ1, 2π, segments, _color, transparency = true)
    push!(whirls, whirl)
    push!(_whirls, _whirl)
end

ps = [GLMakie.Point3f(0.0, 0.0, 0.0) for _ in 1:3]
tails = []
heads = []
arrowcolors = []
for i in 1:segments
    hue = Int(floor(i / segments * 360.0))
    arrowcolor = GLMakie.Observable([GLMakie.HSVA(hue, 100, 100, 1.0), GLMakie.HSVA(hue, 100, 100, 0.5), GLMakie.HSVA(hue, 100, 100, 0.25)])
    push!(arrowcolors, arrowcolor)
    _tails = GLMakie.Observable(ps)
    _heads = GLMakie.Observable(ps)
    push!(tails, _tails)
    push!(heads, _heads)
    GLMakie.arrows!(lscene, _tails, _heads, fxaa = true, color = arrowcolor, linewidth = 0.01, arrowsize = GLMakie.Vec3f(0.02, 0.02, 0.02))
end

linepoints = GLMakie.Observable(GLMakie.Point3f[]) # Signal that can be used to update plots efficiently
linecolors = GLMakie.Observable(Int[])
lines = GLMakie.lines!(lscene, linepoints, linewidth = linewidth, color = linecolors, colormap = :rainbow, transparency = false)
lines.colorrange = (0, frames_number) # update plot attribute directly
starman = FileIO.load("data/Starman_3.stl")
starman_sprite = GLMakie.mesh!(
    lscene,
    starman,
    color = [tri[1][2] for tri in starman for i in 1:3],
    colormap = GLMakie.Reverse(:Spectral)
)
scale = 1 / 400
GLMakie.scale!(starman_sprite, scale, scale, scale)



τ(x, ϕ) = begin
    g = convert_to_geographic(x)
    r, _ϕ, _θ = g
    _ϕ += ϕ
    z₁ = ℯ^(im * 0) * √((1 + sin(_θ)) / 2)
    z₂ = ℯ^(im * _ϕ) * √((1 - sin(_θ)) / 2)
    Quaternion([z₂; z₁])
end


function getcenter(nodes)
    center = [0.0; 0.0; 0.0]
    for i in eachindex(nodes)
        geographic = convert_to_geographic(nodes[i])
        center = center + geographic
    end
    center[1] = 1.0 # the unit spherical Earth
    center[2] = center[2] ./ length(nodes)
    center[3] = center[3] ./ length(nodes)
    convert_to_cartesian(center)
end


function animate(progress, totalprogress, frame)
    q = exp(K(1) * totalprogress * 2π) * τmap(convert_to_geographic([1.0; 0.0; 0.0]))
    index = indices[samplename]
    center = getcenter(boundary_nodes[index])
    r, _ϕ, _θ = convert_to_geographic(center)
    f = 0.9
    h = exp(f * _ϕ / 4 * K(1) + f * _θ / 2 * K(2)) * q
    
    update!(basemap1, q)
    update!(basemap2, G(θ1, q))
    for i in eachindex(boundary_nodes)
        points = Quaternion[]
        for node in boundary_nodes[i]
            r, _ϕ, _θ = convert_to_geographic(node)
            push!(points, exp(f * _ϕ / 4 * K(1) + f * _θ / 2 * K(2)) * q)
        end
        update!(whirls[i], points, θ1, 2π)
        update!(_whirls[i], points, 0.0, θ1)
    end

    α = cos(totalprogress * 2π) * 2π
    θ = sin(progress * 2π) * 2π
    track, track1, track2, track3 = paralleltransport(h, α, θ, segments)
    for i in 1:segments
        x = project(track[i])
        x¹ = normalize(project(track1[i]))
        x² = normalize(project(track2[i]))
        x³ = normalize(project(track3[i]))
        tails[i][] = [GLMakie.Point3f(x...) for _ in 1:3]
        heads[i][] = [GLMakie.Point3f(x¹...), GLMakie.Point3f(x²...), GLMakie.Point3f(x³...)]
        hue = Int(floor(i / segments * 360.0))
        arrowcolors[i][] = [GLMakie.HSVA(hue, 100, 100, 1.0), GLMakie.HSVA(hue, 100, 100, 0.5), GLMakie.HSVA(hue, 100, 100, 0.25)]
    end

    linepoints[] = map(x -> GLMakie.Point3f(project(x)...), track)
    push!(linecolors[], frame)
    notify(linecolors) # tell points and colors that their value has been updated

    ang, u = getrotation(ẑ, [Float64.(normalize(project(track3[end])))...])
    _q = Quaternion(ang / 2, u)
    initial1 = vec(_q * Quaternion([0; ẑ]) * conj(_q))[2:4]
    v = project(normalize(track1[end]))
    ang1, u1 = getrotation(cross(initial1, v), [Float64.(v)...])
    q1 = Quaternion(ang1 / 2, u1)
    rotation = q1 * _q
    rotation = GLMakie.Quaternion(vec(rotation)[2], vec(rotation)[3], vec(rotation)[4], vec(rotation)[1])
    GLMakie.rotate!(starman_sprite, rotation)
    GLMakie.translate!(starman_sprite, GLMakie.Point3f(project(track[end])))
end

updatecamera() = begin
    GLMakie.update_cam!(lscene.scene, GLMakie.Vec3f(eyeposition...), GLMakie.Vec3f(lookat...), GLMakie.Vec3f(up...))
end

GLMakie.record(fig, joinpath("gallery", "$modelname.mp4"), 1:frames_number) do frame
    progress = frame / frames_number
    stage = min(totalstages - 1, Int(floor(totalstages * progress))) + 1
    stageprogress = totalstages * (progress - (stage - 1) * 1.0 / totalstages)
    println("Frame: $frame, Stage: $stage, Total Stages: $totalstages, Progress: $stageprogress")
    animate(stageprogress, progress, frame)
    updatecamera()
end