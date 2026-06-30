/**
 * dwg_bridge.c
 *
 * C bridge implementation: uses LibreDWG's C API to read DWG files
 * and exposes the data via the C-compatible dwg_bridge API.
 */

#define _CRT_NONSTDC_NO_DEPRECATE
#include "dwg_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dwg.h"
#include "dwg_api.h"
#include "bits.h"

/* ── Helpers ────────────────────────────────────────────────────────────── */

static char *dwg_safe_strdup(const char *s) {
    if (!s) return NULL;
    return strdup(s);
}

/* Map libredwg entity type to our enum */
static DWG_EntityType map_entity_type(Dwg_Object *obj) {
    if (!obj) return DWG_ET_UNKNOWN;
    switch (obj->fixedtype) {
        case DWG_TYPE_TEXT:       return DWG_ET_TEXT;
        case DWG_TYPE_MTEXT:      return DWG_ET_MTEXT;
        case DWG_TYPE_ATTDEF:     return DWG_ET_ATTDEF;
        case DWG_TYPE_ATTRIB:     return DWG_ET_ATTRIB;
        case DWG_TYPE_LINE:       return DWG_ET_LINE;
        case DWG_TYPE_POINT:      return DWG_ET_POINT;
        case DWG_TYPE_CIRCLE:     return DWG_ET_CIRCLE;
        case DWG_TYPE_ARC:        return DWG_ET_ARC;
        case DWG_TYPE_ELLIPSE:    return DWG_ET_ELLIPSE;
        case DWG_TYPE_LWPOLYLINE: return DWG_ET_LWPOLYLINE;
        case DWG_TYPE_POLYLINE_2D:return DWG_ET_POLYLINE_2D;
        case DWG_TYPE_POLYLINE_3D:return DWG_ET_POLYLINE_3D;
        case DWG_TYPE_POLYLINE_PFACE: return DWG_ET_POLYLINE_PFACE;
        case DWG_TYPE_POLYLINE_MESH: return DWG_ET_POLYLINE_MESH;
        case DWG_TYPE_SPLINE:     return DWG_ET_SPLINE;
        case DWG_TYPE_INSERT:     return DWG_ET_INSERT;
        case DWG_TYPE_SOLID:      return DWG_ET_SOLID;
        case DWG_TYPE__3DFACE:    return DWG_ET_3DFACE;
        case DWG_TYPE__3DSOLID:   return DWG_ET_3DSOLID;
        case DWG_TYPE_DIMENSION_ALIGNED:  return DWG_ET_DIMENSION_ALIGNED;
        case DWG_TYPE_DIMENSION_LINEAR:   return DWG_ET_DIMENSION_LINEAR;
        case DWG_TYPE_DIMENSION_RADIUS:   return DWG_ET_DIMENSION_RADIAL;
        case DWG_TYPE_DIMENSION_DIAMETER: return DWG_ET_DIMENSION_DIAMETRIC;
        case DWG_TYPE_DIMENSION_ANG2LN:   return DWG_ET_DIMENSION_ANGULAR;
        case DWG_TYPE_DIMENSION_ANG3PT:   return DWG_ET_DIMENSION_ANGULAR3P;
        case DWG_TYPE_DIMENSION_ORDINATE: return DWG_ET_DIMENSION_ORDINATE;
        case DWG_TYPE_HATCH:      return DWG_ET_HATCH;
        case DWG_TYPE_LEADER:     return DWG_ET_LEADER;
        case DWG_TYPE_MULTILEADER:return DWG_ET_MLEADER;
        case DWG_TYPE_IMAGE:      return DWG_ET_IMAGE;
        case DWG_TYPE_VIEWPORT:   return DWG_ET_VIEWPORT;
        case DWG_TYPE_RAY:        return DWG_ET_RAY;
        case DWG_TYPE_XLINE:      return DWG_ET_XLINE;
        case DWG_TYPE_WIPEOUT:    return DWG_ET_WIPEOUT;
        case DWG_TYPE_OLE2FRAME:  return DWG_ET_OLE2FRAME;
        default:                  return DWG_ET_UNKNOWN;
    }
}

/* Resolve a layer name from an entity */
static const char *get_layer_name(Dwg_Object_Entity *ent) {
    if (!ent || !ent->dwg) return "0";
    Dwg_Data *dwg = ent->dwg;
    for (BITCODE_BL i = 0; i < dwg->num_objects; i++) {
        Dwg_Object *obj = &dwg->object[i];
        if (obj->fixedtype == DWG_TYPE_LAYER) {
            Dwg_Object_LAYER *layer = obj->tio.object->tio.LAYER;
            if (layer && obj->handle.value == ent->layer->absolute_ref) {
                return layer->name;
            }
        }
    }
    return "0";
}

/* ── Entity extraction ──────────────────────────────────────────────────── */

static int extract_entity(Dwg_Object *obj, DWG_EntityData *out) {
    memset(out, 0, sizeof(DWG_EntityData));

    if (!obj || !obj->tio.entity) return 0;

    Dwg_Object_Entity *ent = obj->tio.entity;

    out->type = map_entity_type(obj);

    /* Common properties */
    out->layerName = dwg_safe_strdup(get_layer_name(ent));
    out->color = ent->color.index;
    out->colorRGB = ent->color.rgb;
    out->lineWeight = ent->linewt;
    out->invisible = ent->invisible;

    switch (obj->fixedtype) {
        case DWG_TYPE_LINE: {
            Dwg_Entity_LINE *e = ent->tio.LINE;
            if (e) {
                out->basePoint.x = e->start.x;
                out->basePoint.y = e->start.y;
                out->basePoint.z = e->start.z;
                out->secPoint.x = e->end.x;
                out->secPoint.y = e->end.y;
                out->secPoint.z = e->end.z;
                out->thickness = e->thickness;
                out->extrusion.x = e->extrusion.x;
                out->extrusion.y = e->extrusion.y;
                out->extrusion.z = e->extrusion.z;
            }
            break;
        }
        case DWG_TYPE_POINT: {
            Dwg_Entity_POINT *e = ent->tio.POINT;
            if (e) {
                out->basePoint.x = e->x;
                out->basePoint.y = e->y;
                out->basePoint.z = e->z;
                out->thickness = e->thickness;
            }
            break;
        }
        case DWG_TYPE_CIRCLE: {
            Dwg_Entity_CIRCLE *e = ent->tio.CIRCLE;
            if (e) {
                out->basePoint.x = e->center.x;
                out->basePoint.y = e->center.y;
                out->basePoint.z = e->center.z;
                out->radius = e->radius;
                out->thickness = e->thickness;
                out->extrusion.x = e->extrusion.x;
                out->extrusion.y = e->extrusion.y;
                out->extrusion.z = e->extrusion.z;
            }
            break;
        }
        case DWG_TYPE_ARC: {
            Dwg_Entity_ARC *e = ent->tio.ARC;
            if (e) {
                out->basePoint.x = e->center.x;
                out->basePoint.y = e->center.y;
                out->basePoint.z = e->center.z;
                out->radius = e->radius;
                out->startAngle = e->start_angle;
                out->endAngle = e->end_angle;
                out->thickness = e->thickness;
                out->extrusion.x = e->extrusion.x;
                out->extrusion.y = e->extrusion.y;
                out->extrusion.z = e->extrusion.z;
            }
            break;
        }
        case DWG_TYPE_ELLIPSE: {
            Dwg_Entity_ELLIPSE *e = ent->tio.ELLIPSE;
            if (e) {
                out->basePoint.x = e->center.x;
                out->basePoint.y = e->center.y;
                out->basePoint.z = e->center.z;
                out->secPoint.x = e->sm_axis.x;
                out->secPoint.y = e->sm_axis.y;
                out->secPoint.z = e->sm_axis.z;
                out->axisRatio = e->axis_ratio;
                out->startAngle = e->start_angle;
                out->endAngle = e->end_angle;
                out->extrusion.x = e->extrusion.x;
                out->extrusion.y = e->extrusion.y;
                out->extrusion.z = e->extrusion.z;
            }
            break;
        }
        case DWG_TYPE_LWPOLYLINE: {
            Dwg_Entity_LWPOLYLINE *e = ent->tio.LWPOLYLINE;
            if (e && e->num_points > 0) {
                out->vertexCount2D = (int)e->num_points;
                out->vertices2D = malloc(sizeof(DWG_Vertex2D) * e->num_points);
                if (out->vertices2D) {
                    for (BITCODE_BL i = 0; i < e->num_points; i++) {
                        out->vertices2D[i].x = e->points[i].x;
                        out->vertices2D[i].y = e->points[i].y;
                        out->vertices2D[i].bulge =
                            (e->bulges && i < e->num_bulges) ? e->bulges[i] : 0.0;
                    }
                }
                out->polyFlags = e->flag;
                out->thickness = e->thickness;
                out->extrusion.x = e->extrusion.x;
                out->extrusion.y = e->extrusion.y;
                out->extrusion.z = e->extrusion.z;
            }
            break;
        }
        case DWG_TYPE_POLYLINE_2D:
        case DWG_TYPE_POLYLINE_3D: {
            Dwg_Entity_POLYLINE_2D *e = ent->tio.POLYLINE_2D;
            if (e) {
                out->polyFlags = e->flag;
            }
            break;
        }
        case DWG_TYPE_SPLINE: {
            Dwg_Entity_SPLINE *e = ent->tio.SPLINE;
            if (e) {
                out->splineDegree = (int)e->degree;
                out->splineNKnots = (int)e->num_knots;
                if (e->knots && e->num_knots > 0) {
                    out->splineKnots = malloc(sizeof(double) * e->num_knots);
                    if (out->splineKnots)
                        memcpy(out->splineKnots, e->knots, sizeof(double) * e->num_knots);
                }
                out->splineNControl = (int)e->num_ctrl_pts;
                if (e->ctrl_pts && e->num_ctrl_pts > 0) {
                    out->splineCtrlPts = malloc(sizeof(DWG_Coord) * e->num_ctrl_pts);
                    if (out->splineCtrlPts) {
                        for (BITCODE_BL i = 0; i < e->num_ctrl_pts; i++) {
                            out->splineCtrlPts[i].x = e->ctrl_pts[i].x;
                            out->splineCtrlPts[i].y = e->ctrl_pts[i].y;
                            out->splineCtrlPts[i].z = e->ctrl_pts[i].z;
                        }
                    }
                }
                out->splineNFit = (int)e->num_fit_pts;
                if (e->fit_pts && e->num_fit_pts > 0) {
                    out->splineFitPts = malloc(sizeof(DWG_Coord) * e->num_fit_pts);
                    if (out->splineFitPts) {
                        for (BITCODE_BL i = 0; i < e->num_fit_pts; i++) {
                            out->splineFitPts[i].x = e->fit_pts[i].x;
                            out->splineFitPts[i].y = e->fit_pts[i].y;
                            out->splineFitPts[i].z = e->fit_pts[i].z;
                        }
                    }
                }
            }
            break;
        }
        case DWG_TYPE_TEXT:
        case DWG_TYPE_ATTDEF:
        case DWG_TYPE_ATTRIB: {
            Dwg_Entity_TEXT *e = ent->tio.TEXT;
            if (e) {
                out->basePoint.x = e->ins_pt.x;
                out->basePoint.y = e->ins_pt.y;
                out->basePoint.z = e->elevation;
                out->textHeight = e->height;
                out->textRotation = e->rotation;
                out->textWidthScale = e->width_factor;
                out->textAlignH = (int)e->horiz_alignment;
                out->textAlignV = (int)e->vert_alignment;
                out->textValue = dwg_safe_strdup(e->text_value);
                out->thickness = e->thickness;
            }
            break;
        }
        case DWG_TYPE_MTEXT: {
            Dwg_Entity_MTEXT *e = ent->tio.MTEXT;
            if (e) {
                out->basePoint.x = e->ins_pt.x;
                out->basePoint.y = e->ins_pt.y;
                out->basePoint.z = e->ins_pt.z;
                out->textHeight = e->text_height;
                out->secPoint.x = e->x_axis_dir.x;
                out->secPoint.y = e->x_axis_dir.y;
                out->secPoint.z = e->x_axis_dir.z;
                out->textValue = dwg_safe_strdup(e->text);
            }
            break;
        }
        case DWG_TYPE_INSERT: {
            Dwg_Entity_INSERT *e = ent->tio.INSERT;
            if (e) {
                out->basePoint.x = e->ins_pt.x;
                out->basePoint.y = e->ins_pt.y;
                out->basePoint.z = e->ins_pt.z;
                out->xscale = e->scale.x;
                out->yscale = e->scale.y;
                out->zscale = e->scale.z;
                out->insertAngle = e->rotation;
                out->colCount = (int)e->num_cols;
                out->rowCount = (int)e->num_rows;
                out->colSpace = e->col_spacing;
                out->rowSpace = e->row_spacing;
            }
            break;
        }
        case DWG_TYPE_SOLID: {
            Dwg_Entity_SOLID *e = ent->tio.SOLID;
            if (e) {
                out->basePoint.x = e->corner1.x;
                out->basePoint.y = e->corner1.y;
                out->secPoint.x = e->corner2.x;
                out->secPoint.y = e->corner2.y;
                out->thirdPoint.x = e->corner3.x;
                out->thirdPoint.y = e->corner3.y;
                out->fourPoint.x = e->corner4.x;
                out->fourPoint.y = e->corner4.y;
                out->thickness = e->thickness;
            }
            break;
        }
        case DWG_TYPE__3DFACE: {
            Dwg_Entity__3DFACE *e = ent->tio._3DFACE;
            if (e) {
                out->basePoint.x = e->corner1.x;
                out->basePoint.y = e->corner1.y;
                out->basePoint.z = e->corner1.z;
                out->secPoint.x = e->corner2.x;
                out->secPoint.y = e->corner2.y;
                out->secPoint.z = e->corner2.z;
                out->thirdPoint.x = e->corner3.x;
                out->thirdPoint.y = e->corner3.y;
                out->thirdPoint.z = e->corner3.z;
                out->fourPoint.x = e->corner4.x;
                out->fourPoint.y = e->corner4.y;
                out->fourPoint.z = e->corner4.z;
            }
            break;
        }
        case DWG_TYPE_HATCH: {
            Dwg_Entity_HATCH *e = ent->tio.HATCH;
            if (e) {
                out->hatchSolid = e->is_solid_fill;
                out->hatchPatternName = dwg_safe_strdup(e->name);
                out->hatchScale = e->scale_spacing;
                out->hatchAngle = e->angle;
                out->extrusion.x = e->extrusion.x;
                out->extrusion.y = e->extrusion.y;
                out->extrusion.z = e->extrusion.z;
            }
            break;
        }
        case DWG_TYPE_IMAGE: {
            Dwg_Entity_IMAGE *e = ent->tio.IMAGE;
            if (e) {
                out->imageBrightness = (double)e->brightness;
                out->imageContrast = (double)e->contrast;
                out->imageFade = (double)e->fade;
            }
            break;
        }
        case DWG_TYPE_DIMENSION_ALIGNED:
        case DWG_TYPE_DIMENSION_LINEAR:
        case DWG_TYPE_DIMENSION_RADIUS:
        case DWG_TYPE_DIMENSION_DIAMETER:
        case DWG_TYPE_DIMENSION_ANG2LN:
        case DWG_TYPE_DIMENSION_ANG3PT:
        case DWG_TYPE_DIMENSION_ORDINATE: {
            /* All dimension types share DIMENSION_COMMON fields via macro */
            Dwg_DIMENSION_common *e = ent->tio.DIMENSION_common;
            if (e) {
                out->dimText = dwg_safe_strdup(e->user_text);
                out->dimDefPoint.x = e->def_pt.x;
                out->dimDefPoint.y = e->def_pt.y;
                out->dimDefPoint.z = e->def_pt.z;
                out->dimTextPoint.x = e->text_midpt.x;
                out->dimTextPoint.y = e->text_midpt.y;
                out->dimTextPoint.z = e->elevation;
                out->dimAngle = e->text_rotation;
            }
            break;
        }
        default:
            break;
    }

    return 1;
}

/* ── Layer extraction ───────────────────────────────────────────────────── */

static int extract_layers(Dwg_Data *dwg, DWG_LayerData **outLayers, int *outCount) {
    *outCount = 0;
    *outLayers = NULL;
    if (!dwg) return 0;

    /* Count layers */
    int layerCount = 0;
    for (BITCODE_BL i = 0; i < dwg->num_objects; i++) {
        if (dwg->object[i].fixedtype == DWG_TYPE_LAYER) layerCount++;
    }

    DWG_LayerData *layers = calloc(layerCount, sizeof(DWG_LayerData));
    if (!layers) return 0;
    if (layerCount == 0) { *outLayers = layers; return 1; }

    int idx = 0;
    for (BITCODE_BL i = 0; i < dwg->num_objects; i++) {
        Dwg_Object *obj = &dwg->object[i];
        if (obj->fixedtype != DWG_TYPE_LAYER) continue;
        Dwg_Object_LAYER *layer = obj->tio.object->tio.LAYER;
        if (!layer) continue;

        layers[idx].name = dwg_safe_strdup(layer->name);
        layers[idx].color = layer->color.index;
        layers[idx].colorRGB = layer->color.rgb;
        layers[idx].lineWeight = layer->linewt;
        layers[idx].on = layer->off ? 0 : 1;  /* off=1 means OFF */
        layers[idx].frozen = layer->frozen;
        layers[idx].locked = layer->locked;
        layers[idx].plotFlag = layer->plotflag;
        idx++;
    }

    *outLayers = layers;
    *outCount = idx;
    return 1;
}

/* ── Block extraction ───────────────────────────────────────────────────── */

static int extract_blocks(Dwg_Data *dwg, DWG_BlockData **outBlocks, int *outCount) {
    *outCount = 0;
    *outBlocks = NULL;
    if (!dwg) return 0;

    int blockCount = 0;
    for (BITCODE_BL i = 0; i < dwg->num_objects; i++) {
        if (dwg->object[i].fixedtype == DWG_TYPE_BLOCK_HEADER) blockCount++;
    }

    DWG_BlockData *blocks = calloc(blockCount, sizeof(DWG_BlockData));
    if (!blocks) return 0;
    if (blockCount == 0) { *outBlocks = blocks; return 1; }

    int idx = 0;
    for (BITCODE_BL i = 0; i < dwg->num_objects; i++) {
        Dwg_Object *obj = &dwg->object[i];
        if (obj->fixedtype != DWG_TYPE_BLOCK_HEADER) continue;
        Dwg_Object_BLOCK_HEADER *bh = obj->tio.object->tio.BLOCK_HEADER;
        if (!bh) continue;

        blocks[idx].name = dwg_safe_strdup(bh->name);
        blocks[idx].basePoint.x = bh->base_pt.x;
        blocks[idx].basePoint.y = bh->base_pt.y;
        blocks[idx].basePoint.z = bh->base_pt.z;
        idx++;
    }

    *outBlocks = blocks;
    *outCount = idx;
    return 1;
}

/* ── Collect entities ───────────────────────────────────────────────────── */

static int collect_entities(Dwg_Data *dwg, DWG_EntityData **outEntities, int *outCount) {
    *outCount = 0;
    *outEntities = NULL;
    if (!dwg) return 0;

    /* First count non-vertex/sub-entities */
    int total = 0;
    for (BITCODE_BL i = 0; i < dwg->num_objects; i++) {
        Dwg_Object *obj = &dwg->object[i];
        if (!obj->tio.entity) continue;
        switch (obj->fixedtype) {
            case DWG_TYPE_VERTEX_2D:
            case DWG_TYPE_VERTEX_3D:
            case DWG_TYPE_VERTEX_MESH:
            case DWG_TYPE_VERTEX_PFACE:
            case DWG_TYPE_VERTEX_PFACE_FACE:
            case DWG_TYPE_SEQEND:
            case DWG_TYPE_ENDBLK:
                continue;
            default: break;
        }
        total++;
    }

    DWG_EntityData *entities = calloc(total, sizeof(DWG_EntityData));
    if (!entities) return 0;

    int count = 0;
    for (BITCODE_BL i = 0; i < dwg->num_objects; i++) {
        Dwg_Object *obj = &dwg->object[i];
        if (!obj->tio.entity) continue;
        switch (obj->fixedtype) {
            case DWG_TYPE_VERTEX_2D:
            case DWG_TYPE_VERTEX_3D:
            case DWG_TYPE_VERTEX_MESH:
            case DWG_TYPE_VERTEX_PFACE:
            case DWG_TYPE_VERTEX_PFACE_FACE:
            case DWG_TYPE_SEQEND:
            case DWG_TYPE_ENDBLK:
                continue;
            default: break;
        }
        if (extract_entity(obj, &entities[count])) count++;
    }

    *outEntities = entities;
    *outCount = count;
    return 1;
}

/* ── Public API ─────────────────────────────────────────────────────────── */

int dwg_bridge_read(const char *filePath, DWG_Result *outResult) {
    if (!filePath || !outResult) return 0;

    memset(outResult, 0, sizeof(DWG_Result));
    Dwg_Data dwg;
    memset(&dwg, 0, sizeof(Dwg_Data));
    dwg.opts = 0;

    int success = dwg_read_file(filePath, &dwg);
    if (!success) {
        outResult->success = 0;
        outResult->errorMessage = strdup("Failed to read DWG file");
        return 0;
    }

    /* Extract metadata */
    outResult->version = dwg.header.version;
    outResult->insUnits = dwg.header_vars.INSUNITS;

    /* Extract layers */
    extract_layers(&dwg, &outResult->layers, &outResult->layerCount);

    /* Extract blocks */
    extract_blocks(&dwg, &outResult->blocks, &outResult->blockCount);

    /* Collect all entities */
    collect_entities(&dwg, &outResult->entities, &outResult->entityCount);

    /* Separate model space and paper space */
    int msCount = 0, psCount = 0;
    for (int i = 0; i < outResult->entityCount; i++) {
        msCount++;  /* default to model space */
    }

    outResult->modelSpaceEntities = calloc(msCount, sizeof(DWG_EntityData));
    outResult->paperSpaceEntities = calloc(psCount, sizeof(DWG_EntityData));

    /* For now, put all entities in model space */
    int msi = 0;
    for (int i = 0; i < outResult->entityCount; i++) {
        if (msi < msCount) {
            memcpy(&outResult->modelSpaceEntities[msi],
                   &outResult->entities[i], sizeof(DWG_EntityData));
            msi++;
        }
    }
    outResult->modelSpaceCount = msi;
    outResult->paperSpaceCount = 0;

    outResult->success = 1;

    dwg_free(&dwg);
    return 1;
}

void dwg_bridge_result_free(DWG_Result *result) {
    if (!result) return;

    for (int i = 0; i < result->entityCount; i++) {
        DWG_EntityData *e = &result->entities[i];
        free(e->layerName);
        free(e->textValue);
        free(e->textStyle);
        free(e->blockName);
        free(e->hatchPatternName);
        free(e->dimText);
        free(e->imageFilePath);
        free(e->vertices2D);
        free(e->vertices3D);
        free(e->splineKnots);
        free(e->splineCtrlPts);
        free(e->splineFitPts);
    }
    free(result->entities);
    free(result->modelSpaceEntities);
    free(result->paperSpaceEntities);

    for (int i = 0; i < result->layerCount; i++) {
        free(result->layers[i].name);
        free(result->layers[i].lineTypeName);
    }
    free(result->layers);

    for (int i = 0; i < result->blockCount; i++) {
        free(result->blocks[i].name);
    }
    free(result->blocks);

    free(result->errorMessage);
    memset(result, 0, sizeof(DWG_Result));
}

/* ── DWG Write ─────────────────────────────────────────────────────────── */

static void write_entity_to_dwg(Dwg_Data *dwg, const DWG_EntityData *e) {
    int error = 0;
    Dwg_Object_BLOCK_HEADER *ms_hdr = dwg_get_block_header(dwg, &error);
    if (error || !ms_hdr) return;

    dwg_point_3d pt = { e->basePoint.x, e->basePoint.y, e->basePoint.z };
    dwg_point_3d pt2 = { e->secPoint.x, e->secPoint.y, e->secPoint.z };

    switch (e->type) {
        case DWG_ET_LINE: {
            Dwg_Entity_LINE *line = dwg_add_LINE(ms_hdr, &pt, &pt2);
            if (line) { line->thickness = e->thickness; }
            break;
        }
        case DWG_ET_CIRCLE: {
            Dwg_Entity_CIRCLE *circle = dwg_add_CIRCLE(ms_hdr, &pt, e->radius);
            if (circle) { circle->thickness = e->thickness; }
            break;
        }
        case DWG_ET_ARC: {
            Dwg_Entity_ARC *arc = dwg_add_ARC(ms_hdr, &pt, e->radius,
                                                e->startAngle, e->endAngle);
            if (arc) { arc->thickness = e->thickness; }
            break;
        }
        case DWG_ET_POINT: {
            Dwg_Entity_POINT *point = dwg_add_POINT(ms_hdr, &pt);
            if (point) { point->thickness = e->thickness; }
            break;
        }
        case DWG_ET_TEXT: {
            const char *text = e->textValue ? e->textValue : "";
            double height = e->textHeight > 0 ? e->textHeight : 2.5;
            Dwg_Entity_TEXT *textent = dwg_add_TEXT(ms_hdr, text, &pt, height);
            if (textent) {
                textent->rotation = e->textRotation;
                textent->horiz_alignment = e->textAlignH;
                textent->vert_alignment = e->textAlignV;
            }
            break;
        }
        case DWG_ET_MTEXT: {
            const char *text = e->textValue ? e->textValue : "";
            double height = e->textHeight > 0 ? e->textHeight : 2.5;
            Dwg_Entity_MTEXT *mtext = dwg_add_MTEXT(ms_hdr, &pt, height, text);
            if (mtext) { mtext->text_height = height; }
            break;
        }
        case DWG_ET_LWPOLYLINE: {
            if (e->vertexCount2D > 0 && e->vertices2D) {
                dwg_point_2d *points = malloc(sizeof(dwg_point_2d) * e->vertexCount2D);
                if (points) {
                    for (int i = 0; i < e->vertexCount2D; i++) {
                        points[i].x = e->vertices2D[i].x;
                        points[i].y = e->vertices2D[i].y;
                    }
                    Dwg_Entity_LWPOLYLINE *pl = dwg_add_LWPOLYLINE(
                        ms_hdr, e->vertexCount2D, points);
                    if (pl) {
                        pl->thickness = e->thickness;
                        if (e->polyFlags & 1) pl->flag |= 1; /* closed */
                    }
                    free(points);
                }
            }
            break;
        }
        case DWG_ET_INSERT: {
            if (e->blockName) {
                dwg_add_INSERT(ms_hdr, &pt, e->blockName,
                               e->xscale, e->yscale, e->zscale, e->insertAngle);
            }
            break;
        }
        case DWG_ET_SOLID: {
            dwg_point_3d c1 = { e->basePoint.x, e->basePoint.y, e->basePoint.z };
            dwg_point_2d c2 = { e->secPoint.x, e->secPoint.y };
            dwg_point_2d c3 = { e->thirdPoint.x, e->thirdPoint.y };
            dwg_point_2d c4 = { e->fourPoint.x, e->fourPoint.y };
            Dwg_Entity_SOLID *solid = dwg_add_SOLID(ms_hdr, &c1, &c2, &c3, &c4);
            if (solid) { solid->thickness = e->thickness; }
            break;
        }
        default:
            break;
    }
}

int dwg_bridge_write(const char *filePath,
                     const DWG_EntityData *entities, int count,
                     int version, char **errorMsg) {
    if (!filePath || !entities || count <= 0) {
        if (errorMsg) *errorMsg = strdup("Invalid arguments");
        return 0;
    }

    Dwg_Data dwg;
    memset(&dwg, 0, sizeof(Dwg_Data));
    dwg.opts = 0;

    /* Set version */
    dwg.header.version = version > 0 ? version : R_2000;

    /* Setup basic header variables */
    dwg.header.from_version = dwg.header.version;
    dwg.header_vars.INSUNITS = 4; /* mm */
    dwg.header_vars.TEXTSIZE = 2.5;
    dwg.header_vars.LIMMIN.x = 0.0;
    dwg.header_vars.LIMMIN.y = 0.0;
    dwg.header_vars.LIMMAX.x = 420.0;
    dwg.header_vars.LIMMAX.y = 297.0;

    /* Write all entities to the DWG */
    for (int i = 0; i < count; i++) {
        write_entity_to_dwg(&dwg, &entities[i]);
    }

    /* Write file */
    int success = dwg_write_file(filePath, &dwg);
    if (!success) {
        if (errorMsg) *errorMsg = strdup("dwg_write_file failed");
    }

    dwg_free(&dwg);
    return success;
}
