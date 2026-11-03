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

  const OFFSET_OFERTA_AR = '-03:00';

  function parseFechaOferta(valor) {
    const texto = String(valor == null ? '' : valor).trim();
    if (!texto) return null;

    let normalizado = texto;
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/.test(texto)) {
      normalizado = texto + (texto.length === 16 ? ':00' : '') + OFFSET_OFERTA_AR;
    }

    const ms = Date.parse(normalizado);
    return Number.isFinite(ms) ? ms : null;
  }

  function ofertaVigente(producto, ahoraMs) {
    if (!producto) return false;

    const ahora = Number.isFinite(ahoraMs) ? ahoraMs : Date.now();

    if (producto.oferta_desde) {
      const desde = parseFechaOferta(producto.oferta_desde);
      if (desde !== null && ahora < desde) return false;
    }

    if (producto.oferta_hasta) {
      const hasta = parseFechaOferta(producto.oferta_hasta);
      if (hasta !== null && ahora > hasta) return false;
    }

    return true;
  }

  function fechaOfertaCorta(valor) {
    const ms = parseFechaOferta(valor);
    if (ms === null) return '';

    const partes = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Argentina/Buenos_Aires',
      day: '2-digit',
      month: '2-digit'
    }).formatToParts(new Date(ms));

    const obtener = (tipo) => {
      const parte = partes.find(item => item.type === tipo);
      return parte ? parte.value : '';
    };

    return `${obtener('day')}/${obtener('month')}`;
  }

  function fechaOfertaLarga(valor) {
    const ms = parseFechaOferta(valor);
    if (ms === null) return '';

    const partes = new Intl.DateTimeFormat('es-AR', {
      timeZone: 'America/Argentina/Buenos_Aires',
      weekday: 'long',
      day: '2-digit',
      month: '2-digit'
    }).formatToParts(new Date(ms));

    const obtener = (tipo) => {
      const parte = partes.find(item => item.type === tipo);
      return parte ? parte.value : '';
    };

    const dia = Number(obtener('day')) || obtener('day');
    return `${obtener('weekday')} ${dia}/${obtener('month')}`;
  }

  function horaOfertaCorta(valor) {
    const ms = parseFechaOferta(valor);
    if (ms === null) return '';

    const partes = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'America/Argentina/Buenos_Aires',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    }).formatToParts(new Date(ms));

    const obtener = (tipo) => {
      const parte = partes.find(item => item.type === tipo);
      return parte ? parte.value : '';
    };

    return `${obtener('hour')}:${obtener('minute')}`;
  }

  function fechaOfertaParaInput(valor) {
    const ms = parseFechaOferta(valor);
    if (ms === null) return '';

    const partes = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Argentina/Buenos_Aires',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    }).formatToParts(new Date(ms));

    const obtener = (tipo) => {
      const parte = partes.find(item => item.type === tipo);
      return parte ? parte.value : '';
    };

    return `${obtener('year')}-${obtener('month')}-${obtener('day')}T${obtener('hour')}:${obtener('minute')}`;
  }

  function inputOfertaAIso(valor) {
    const texto = String(valor == null ? '' : valor).trim();
    if (!texto) return '';

    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(texto)) return '';
    if (parseFechaOferta(texto) === null) return '';

    return `${texto}:00${OFFSET_OFERTA_AR}`;
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
  PM.parseFechaOferta = parseFechaOferta;
  PM.ofertaVigente = ofertaVigente;
  PM.fechaOfertaCorta = fechaOfertaCorta;
  PM.fechaOfertaLarga = fechaOfertaLarga;
  PM.horaOfertaCorta = horaOfertaCorta;
  PM.fechaOfertaParaInput = fechaOfertaParaInput;
  PM.inputOfertaAIso = inputOfertaAIso;
})(window);
