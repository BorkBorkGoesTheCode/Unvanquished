/*
===========================================================================
Copyright (C) 2006-2011 Robert Beckebans <trebor_7@users.sourceforge.net>

This file is part of XreaL source code.

XreaL source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

XreaL source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with XreaL source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/

/* lighttile_fp.glsl */

varying vec2 vPosition;
varying vec2 vTexCoord;

struct light {
  vec4  center_radius;
  vec4  color_type;
  vec4  direction_angle;
};

#ifdef HAVE_ARB_uniform_buffer_object
layout(std140) uniform u_Lights {
  light lights[ MAX_REF_LIGHTS ];
};
#define GetLight(idx, component) lights[idx].component
#else
uniform sampler2D u_Lights;
#define center_radius_offset   0
#define color_type_offset      1
#define direction_angle_offset 2
#define idxToTC( idx, w, h ) vec2( floor( ( idx * ( 1.0 / w ) + 0.5 ) * ( 1.0 / h ) ), \
				   fract( ( idx + 0.5 ) * (1.0 / w ) ) )
#define GetLight(idx, component) texture2D( u_Lights, idxToTC(3 * idx + component##_offset, 64.0, float( 3 * MAX_REF_LIGHTS / 64 ) ) )
#endif

uniform int  u_numLights;
uniform mat4 u_ModelMatrix;
uniform sampler2D u_DepthMap;
uniform int  u_lightLayer;
uniform vec3 u_zFar;

const int numLayers = MAX_REF_LIGHTS / 256;

#if defined( TEXTURE_INTEGER ) && defined( HAVE_EXT_gpu_shader4 )
#define idxs_t uvec4
#define idx_initializer uvec4(3)
#if __VERSION__ < 130
varying out uvec4 fragData;
#else
out uvec4 fragData;
#endif
void pushIdxs(in int idx, inout uvec4 idxs ) {
  uvec4 bits = uvec4( idx >> 8, idx >> 6, idx >> 4, idx >> 2 ) & uvec4( 0x03 );
  idxs = idxs << 2 | bits;
}
#define exportIdxs(x) fragData = ( x )
#else
#define idxs_t vec4
#define idx_initializer vec4(3.0)
void pushIdxs(in int idx, inout vec4 idxs ) {
  vec4 bits = floor( vec4( idx ) * vec4( 1.0/256.0, 1.0/64.0, 1.0/16.0, 1.0/4.0 ) );
  bits.yzw -= 4.0 * bits.xyz;
  idxs = idxs * 4.0 + bits;
  idxs -= 256.0 * floor( idxs * (1.0/256.0) ); // discard upper bits
}
#define exportIdxs(x) gl_FragColor = ( x ) * (1.0/255.0)
#endif

void lightOutsidePlane( in vec4 plane, inout vec3 center, inout float radius ) {
  float dist = dot( plane, vec4( center, 1.0 ) );
  if( dist >= radius ) {
    radius = 0.0; // light completely outside plane
    return;
  }

  if( dist >= 0.0 ) {
    // light is outside plane, but intersects the volume
    center = center - dist * plane.xyz;
    radius = sqrt( radius * radius - dist * dist );
  }
}

vec3 ProjToView(vec2 inp)
{
	vec3 p = u_zFar * vec3(inp, -1);
	
	return p;
}

void main() {
  vec2 minmax = texture2D( u_DepthMap, 0.5 * vPosition + 0.5 ).xy;

  float minx = vPosition.x - r_tileStep.x;
  float maxx = vPosition.x + r_tileStep.x;
  float miny = vPosition.y - r_tileStep.y;
  float maxy = vPosition.y + r_tileStep.y;

  vec3 bottomleft = ProjToView(vec2(minx, miny));
  vec3 bottomright = ProjToView(vec2(maxx, miny));
  vec3 topright = ProjToView(vec2(maxx, maxy));
  vec3 topleft = ProjToView(vec2(minx, maxy));

  vec4 plane1 = vec4(normalize(cross(bottomleft, bottomright)), 0);
  vec4 plane2 = vec4(normalize(cross(bottomright, topright)), 0);
  vec4 plane3 = vec4(normalize(cross(topright, topleft)), 0);
  vec4 plane4 = vec4(normalize(cross(topleft, bottomleft)), 0);

  vec4 plane5 = vec4( 0.0, 0.0,  1.0,  minmax.y );
  vec4 plane6 = vec4( 0.0, 0.0, -1.0, -minmax.x );

  idxs_t idxs = idx_initializer;

  for( int i = u_lightLayer; i < u_numLights; i += numLayers ) {
    vec4 center_radius = GetLight( i, center_radius );
    vec3 center = ( u_ModelMatrix * vec4( center_radius.xyz, 1.0 ) ).xyz;
    float radius = 2.0 * center_radius.w;

    // todo: better checks for spotlights
    lightOutsidePlane( plane1, center, radius );
    lightOutsidePlane( plane2, center, radius );
    lightOutsidePlane( plane3, center, radius );
    lightOutsidePlane( plane4, center, radius );
    lightOutsidePlane( plane5, center, radius );
    lightOutsidePlane( plane6, center, radius );

    if( radius > 0.0 ) {
      pushIdxs( i, idxs );
    }
  }

  exportIdxs( idxs );
}
