#ifndef RASTERIZER_H
#define RASTERIZER_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/classes/image.hpp>
namespace godot {
/*struct SubChunkDataPointers {
    uint8_t* vegetation_ptr = nullptr;
    uint8_t* logic_map_ptr = nullptr;
};*/
class RasterizerUtils : public Node {
    GDCLASS(RasterizerUtils, Node)

private:
    

protected:
    static void _bind_methods();

public:
    RasterizerUtils();
    ~RasterizerUtils();
    static Variant rasterize_tile_data_safe(const Dictionary &safe_mvt_data, const Dictionary &config);
    static Variant rasterize_tile_data_safe_fast_butZfight(const Dictionary &safe_mvt_data, const Dictionary &config);
    static Variant rasterize_tile_data_safe_slow(const Dictionary &safe_mvt_data, const Dictionary &config);
    //static Variant rasterize_tile_data_fast(const Variant &mvt_tile_variant, const Dictionary &config);
};

}
//static bool compare_edges(const Edge &a, const Edge &b);
#endif // RASTERIZER_H


