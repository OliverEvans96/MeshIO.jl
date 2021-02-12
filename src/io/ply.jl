#=
From http://paulbourke.net/dataformats/ply/

name        type        number of bytes
---------------------------------------
char       character                 1
uchar      unsigned character        1
short      short integer             2
ushort     unsigned short integer    2
int        integer                   4
uint       unsigned integer          4
float      single-precision float    4
double     double-precision float    8
=#
typemap = Dict(
    Char => "char",
    UInt8 => "uchar",
    Int16 => "short",
    UInt16 => "ushort",
    Int32 => "int",
    Int32 => "uint",
    Float32 => "float",
    Float64 => "double",
)


function save(f::Stream{format"PLY_BINARY"}, msh::AbstractMesh)
    io = stream(f)
    points = decompose(Point{3, Float32}, msh)
    faces = decompose(GLTriangleFace, msh)

    n_points = length(points)
    n_faces = length(faces)

    # write the header
    write(io, "ply\n")
    write(io, "format binary_little_endian 1.0\n")
    write(io, "element vertex $n_points\n")
    write(io, "property float x\nproperty float y\nproperty float z\n")
    write(io, "element face $n_faces\n")
    write(io, "property list uchar int vertex_index\n")
    write(io, "end_header\n")

    # write the vertices and faces
    write(io, points)

    for f in faces
        write(io, convert(UInt8, 3))
        write(io, raw.(f)...)
    end
    close(io)
end

function save(f::Stream{format"PLY_ASCII"}, msh::AbstractMesh)
    io = stream(f)
    points = coordinates(msh)
    meshfaces = faces(msh)

    n_faces = length(points)
    n_points = length(meshfaces)

    point_type = eltype(points)
    if point_type <: PointMeta
        metafields = point_type.parameters[4]
        metatypes = point_type.parameters[5].parameters
    else
        metafields = []
        metatypes = []
    end

    # write the header
    write(io, "ply\n")
    write(io, "format ascii 1.0\n")
    write(io, "element vertex $n_faces\n")
    write(io, "property float x\nproperty float y\nproperty float z\n")
    for (metafield, metatype) in zip(metafields, metatypes)
        type = typemap[metatype]
        write(io, "property $type $metafield\n")
    end
    write(io, "element face $n_points\n")
    write(io, "property list uchar int vertex_index\n")
    write(io, "end_header\n")

    # write the vertices and faces
    for v in points
        metavals = map(f -> getproperty(v, f), metafields)
        print(io, join(Point{3, Float32}(v), " "))
        print(io, " ")
        print(io, join(metavals, " "))
        print(io, "\n")

    end
    for f in meshfaces
        println(io, length(f), " ", join(raw.(ZeroIndex.(f)), " "))
    end
    close(io)
end

function load(fs::Stream{format"PLY_ASCII"}; facetype=GLTriangleFace, pointtype=Point3f0)
    io = stream(fs)
    n_points = 0
    n_faces = 0

    properties = String[]

    # read the header
    line = readline(io)

    while !startswith(line, "end_header")
        if startswith(line, "element vertex")
            n_points = parse(Int, split(line)[3])
        elseif startswith(line, "element face")
            n_faces = parse(Int, split(line)[3])
        elseif startswith(line, "property")
            push!(properties, line)
        end
        line = readline(io)
    end

    faceeltype = eltype(facetype)
    points = Array{pointtype}(undef, n_points)
    #faces = Array{FaceType}(undef, n_faces)
    faces = facetype[]

    # read the data
    for i = 1:n_points
        points[i] = pointtype(parse.(eltype(pointtype), split(readline(io)))) # line looks like: "-0.018 0.038 0.086"
    end

    for i = 1:n_faces
        line = split(readline(io))
        len = parse(Int, popfirst!(line))
        if len == 3
            push!(faces, NgonFace{3, faceeltype}(reinterpret(ZeroIndex{Int}, parse.(Int, line)))) # line looks like: "3 0 1 3"
        elseif len == 4
            push!(faces, convert_simplex(facetype, QuadFace{faceeltype}(reinterpret(ZeroIndex{Int}, parse.(Int, line))))...) # line looks like: "4 0 1 2 3"
        end
    end
    return Mesh(points, faces)
end
