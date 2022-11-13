/* GstShark - A Front End for GstTracer
 * Copyright (C) 2016 RidgeRun Engineering <carlos.rodriguez@ridgerun.com>
 *
 * This file is part of GstShark.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#ifndef __GST_SCHEDULETIME_TRACER_HPP__
#define __GST_SCHEDULETIME_TRACER_HPP__

#include "gstsharktracer.hpp"

G_BEGIN_DECLS

#define GST_TYPE_SCHEDULETIME_TRACER (gst_scheduletime_tracer_get_type ())
G_DECLARE_FINAL_TYPE (GstScheduletimeTracer, gst_scheduletime_tracer, GST, SCHEDULETIME_TRACER, GstSharkTracer)

G_END_DECLS

#endif /* __GST_SCHEDULETIME_TRACER_HPP__ */
