/* ===== Piedra Mora - utilidades compartidas (Fase 0) ===== */
(function (window) {
  'use strict';

  const PM = window.PM = window.PM || {};

  function hoyArgentina() {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Argentina/Buenos_Aires',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(new Date());
  }

  function escaparHtml(valor) {
    return String(valor == null ? '' : valor).replace(/[&<>"']/g, (caracter) => {
      switch (caracter) {
        case '&': return '&amp;';
        case '<': return '&lt;';
        case '>': return '&gt;';
        case '"': return '&quot;';
        case "'": return '&#39;';
        default: return caracter;
      }
    });
  }

  function esRutaImagenSegura(valor) {
    const ruta = String(valor || '').trim();
    if (!ruta) return false;
    if (/['"\\\n\r]/.test(ruta)) return false;
    if (/^data:image\/(png|jpe?g|webp|avif|gif);base64,/i.test(ruta)) return true;
    if (/^https?:\/\//i.test(ruta)) return true;
    if (/^\/\//.test(ruta)) return true;
    if (/^[a-z][a-z0-9+.-]*:/i.test(ruta)) return false;
    return true;
  }

  function urlImagenSegura(valor, fallback) {
    return esRutaImagenSegura(valor) ? String(valor).trim() : fallback;
  }

  function urlExternaSegura(valor, fallback) {
    const ruta = String(valor || '').trim();
    return /^https?:\/\//i.test(ruta) ? ruta : fallback;
  }

  function productoEstaAgotado(producto, fechaHoy) {
    if (!producto || producto.agotado !== true) return false;
    if (producto.agotado_hasta_nuevo_aviso === true) return true;
    return producto.agotado_fecha === (fechaHoy || hoyArgentina());
  }

  function normalizarAgotado(producto, fechaHoy) {
    if (!producto || typeof producto !== 'object') return producto;

    const hoy = fechaHoy || hoyArgentina();

    if (producto.agotado !== true) {
      producto.agotado = false;
      producto.agotado_fecha = null;
      producto.agotado_hasta_nuevo_aviso = false;
      return producto;
    }

    if (producto.agotado_hasta_nuevo_aviso === true) {
      producto.agotado = true;
      if (!producto.agotado_fecha) producto.agotado_fecha = hoy;
      return producto;
    }

    if (producto.agotado_fecha !== hoy) {
      producto.agotado = false;
      producto.agotado_fecha = null;
      producto.agotado_hasta_nuevo_aviso = false;
    }

    return producto;
  }

  PM.hoyArgentina = hoyArgentina;
  PM.escaparHtml = escaparHtml;
  PM.esRutaImagenSegura = esRutaImagenSegura;
  PM.urlImagenSegura = urlImagenSegura;
  PM.urlExternaSegura = urlExternaSegura;
  PM.productoEstaAgotado = productoEstaAgotado;
  PM.normalizarAgotado = normalizarAgotado;
})(window);
