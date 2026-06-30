/**
 * dwg_bridge.h
 *
 * C-compatible bridge between LibreDWG and Swift.
 *
 * This header defines POD structs for DWG entities, layers, and blocks,
 * plus a simple extern "C" API that Swift can call via a Clang module.
 *
 * The implementation (dwg_bridge.c) uses LibreDWG's C API internally
 * to parse DWG files and populate these structs.
 */

#ifndef DWG_BRIDGE_H
#define DWG_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* ── Coordinate ─────────────────────────────────────────────────────────── */

typedef struct {
  double x;
  double y;
  double z;
} DWG_Coord;

/* ── Entity type enum ───────────────────────────────────────────────────── */

typedef enum {
  DWG_ET_UNKNOWN = 0,
  DWG_ET_TEXT = 1,
  DWG_ET_MTEXT = 2,
  DWG_ET_ATTDEF = 3,
  DWG_ET_ATTRIB = 4,
  DWG_ET_LINE = 5,
  DWG_ET_POINT = 6,
  DWG_ET_CIRCLE = 7,
  DWG_ET_ARC = 8,
  DWG_ET_ELLIPSE = 9,
  DWG_ET_LWPOLYLINE = 10,
  DWG_ET_POLYLINE_2D = 11,
  DWG_ET_POLYLINE_3D = 12,
  DWG_ET_POLYLINE_PFACE = 13,
  DWG_ET_POLYLINE_MESH = 14,
  DWG_ET_SPLINE = 15,
  DWG_ET_INSERT = 16,
  DWG_ET_SOLID = 17,
  DWG_ET_3DFACE = 18,
  DWG_ET_3DSOLID = 19,
  DWG_ET_DIMENSION_ALIGNED = 20,
  DWG_ET_DIMENSION_LINEAR = 21,
  DWG_ET_DIMENSION_RADIAL = 22,
  DWG_ET_DIMENSION_DIAMETRIC = 23,
  DWG_ET_DIMENSION_ANGULAR = 24,
  DWG_ET_DIMENSION_ANGULAR3P = 25,
  DWG_ET_DIMENSION_ORDINATE = 26,
  DWG_ET_HATCH = 27,
  DWG_ET_LEADER = 28,
  DWG_ET_MLEADER = 29,
  DWG_ET_IMAGE = 30,
  DWG_ET_VIEWPORT = 31,
  DWG_ET_RAY = 32,
  DWG_ET_XLINE = 33,
  DWG_ET_WIPEOUT = 34,
  DWG_ET_OLE2FRAME = 35,
} DWG_EntityType;

/* ── Vertex ─────────────────────────────────────────────────────────────── */

typedef struct {
  double x;
  double y;
  double bulge;
} DWG_Vertex2D;

typedef struct {
  double x;
  double y;
  double z;
} DWG_Vertex3D;

/* ── Entity data (tagged union) ─────────────────────────────────────────── */

typedef struct {
  DWG_EntityType type;

  /* Common to all entities */
  char *layerName;     /* layer name (strdup'd, caller frees via dwg_result_free) */
  int color;           /* AutoCAD Color Index (ACI), 256 = ByLayer, 0 = ByBlock */
  int colorRGB;        /* 24-bit RGB if color is a true color, -1 otherwise */
  double lineWeight;   /* mm, -1 = ByLayer */
  int lineTypeScale;   /* entity line type scale factor (whole number) */
  int invisible;       /* 1 if entity is invisible */

  /* Geometry fields — which ones are valid depends on `type` */

  /* POINT, LINE, CIRCLE, ARC, ELLIPSE, TEXT, MTEXT, INSERT, SOLID, 3DFACE */
  DWG_Coord basePoint; /* primary insertion / center point */

  /* LINE, ELLIPSE, TEXT (secondary alignment / end point) */
  DWG_Coord secPoint; /* second point (end of line, major axis end) */

  /* SOLID, 3DFACE */
  DWG_Coord thirdPoint; /* third point */
  DWG_Coord fourPoint;  /* fourth point */

  /* CIRCLE, ARC */
  double radius; /* circle/arc radius */

  /* ARC, ELLIPSE */
  double startAngle; /* radians */
  double endAngle;   /* radians */

  /* ELLIPSE */
  double axisRatio; /* ratio of minor to major axis */

  /* LWPOLYLINE, POLYLINE_2D, POLYLINE_3D */
  int vertexCount2D;
  DWG_Vertex2D *vertices2D; /* array of 2D vertices (LWPOLYLINE, POLYLINE_2D) */

  int vertexCount3D;
  DWG_Vertex3D *vertices3D; /* array of 3D vertices (POLYLINE_3D) */

  int polyFlags; /* closed=1, curve-fit, spline-fit, etc */

  /* TEXT, MTEXT, ATTDEF, ATTRIB */
  char *textValue;       /* text string (UTF-8) */
  double textHeight;     /* text height */
  double textRotation;   /* rotation angle (radians) */
  double textWidthScale; /* width factor */
  char *textStyle;       /* text style name */
  int textAlignH;        /* horizontal alignment: 0=left, 1=center, 2=right, 3=aligned, 4=middle, 5=fit */
  int textAlignV;        /* vertical alignment: 0=baseline, 1=bottom, 2=middle, 3=top */

  /* INSERT (block reference) */
  char *blockName;       /* referenced block name */
  double xscale;
  double yscale;
  double zscale;
  double insertAngle;    /* rotation (radians) */
  int colCount;
  int rowCount;
  double colSpace;
  double rowSpace;

  /* SPLINE */
  int splineDegree;
  int splineNKnots;
  double *splineKnots;       /* knot values */
  int splineNControl;
  DWG_Coord *splineCtrlPts;  /* control points */
  int splineNFit;
  DWG_Coord *splineFitPts;   /* fit points */

  /* HATCH */
  int hatchSolid;            /* 1 = solid fill */
  char *hatchPatternName;
  double hatchScale;
  double hatchAngle;

  /* Extrusion direction (for 2D entities) */
  DWG_Coord extrusion;

  /* Dimension data */
  char *dimText;             /* dimension text override */
  char *dimStyle;
  DWG_Coord dimDefPoint;     /* definition point */
  DWG_Coord dimTextPoint;    /* text midpoint */
  double dimAngle;           /* rotation angle for linear dims */
  double dimLeaderLength;    /* leader length */

  /* IMAGE */
  char *imageFilePath;       /* resolved image path */
  double imageBrightness;
  double imageContrast;
  double imageFade;

  /* Thickness (for extruded 2D entities) */
  double thickness;

} DWG_EntityData;

/* ── Layer data ─────────────────────────────────────────────────────────── */

typedef struct {
  char *name;
  int color;            /* ACI */
  int colorRGB;         /* 24-bit RGB, -1 = not set */
  double lineWeight;    /* mm, -1 = Default */
  int on;               /* 1 = on, 0 = off */
  int frozen;
  int locked;
  int plotFlag;
  char *lineTypeName;
} DWG_LayerData;

/* ── Block data ─────────────────────────────────────────────────────────── */

typedef struct {
  char *name;
  DWG_Coord basePoint;
  char *blockName;         /* parent block name for entities inside this block */
} DWG_BlockData;

/* ── Result struct ──────────────────────────────────────────────────────── */

typedef struct {
  /* Dynamically allocated arrays */
  DWG_LayerData *layers;
  int layerCount;

  DWG_BlockData *blocks;
  int blockCount;

  DWG_EntityData *entities;
  int entityCount;

  DWG_EntityData *modelSpaceEntities;
  int modelSpaceCount;

  DWG_EntityData *paperSpaceEntities;
  int paperSpaceCount;

  /* DWG metadata */
  double insUnits;      /* drawing units (1=inches, 4=mm, 6=meters, etc.) */
  int version;          /* DWG version code (R13=12, R14=13, R2000=14, ...) */

  /* Error info */
  int success;          /* 1 if parse succeeded, 0 on error */
  char *errorMessage;   /* error description, or NULL */
} DWG_Result;

/* ── API ────────────────────────────────────────────────────────────────── */

/**
 * Read a DWG file and extract all entities, layers, and blocks.
 *
 * @param filePath  Path to the DWG file.
 * @param outResult Pointer to a DWG_Result that will be populated.
 *                  The caller must free this with dwg_result_free().
 * @return 1 on success, 0 on failure (error info in outResult->errorMessage).
 */
int dwg_bridge_read(const char *filePath, DWG_Result *outResult);

/**
 * Free all memory allocated by dwg_bridge_read().
 * After calling this, the DWG_Result struct is zeroed.
 */
void dwg_bridge_result_free(DWG_Result *result);

/**
 * Write entities to a DWG file using LibreDWG's write API.
 *
 * @param filePath   Path to the output DWG file.
 * @param entities   Array of entity data to write.
 * @param count      Number of entities.
 * @param version    DWG version code (e.g. 14 for R2000, 24 for R2007).
 * @param errorMsg   Output pointer for error message (caller frees).
 * @return 1 on success, 0 on failure.
 */
int dwg_bridge_write(const char *filePath,
                     const DWG_EntityData *entities, int count,
                     int version, char **errorMsg);

#ifdef __cplusplus
}
#endif

#endif /* DWG_BRIDGE_H */
