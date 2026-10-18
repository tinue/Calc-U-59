#pragma once
#include "CueCard.hpp"
#include <QRectF>

class QPainter;

// Paints a cue card on its template artwork: title (and id), MagnetCard bank
// badges, the A′–E′ / A–E label grid with \blank spans (or free-text rows),
// and the top shadow wash. Layout rules come from Shared/CueCard; this is the
// counterpart of App/Views/CueCardView.swift.
namespace CueCardRenderer {

void paint(QPainter& p, const QRectF& rect, const cu59::CueCardContent& card);

} // namespace CueCardRenderer
