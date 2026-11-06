(() => {
  'use strict';

  const RUTA_CONFIG = 'data/nube.json';
  const RUTA_CARTA_LOCAL = 'data/cartas.json';
  const BUCKET_IMAGENES = 'carta-imagenes';
  const TAMANO_MAXIMO_IMAGEN = 5 * 1024 * 1024;
  const TIPOS_IMAGEN = ['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/gif'];
  const CLAVE_PREF_SONIDO = 'piedraMoraAdminSonido';
  const CLAVE_PREF_VOLUMEN = 'piedraMoraAdminVolumen';
  const INTERVALO_ALERTA_PEDIDOS = 8000;
  let SUCURSALES_POR_DEFECTO = ['maestro-quiroga', 'intendente-lascano'];
  let SUCURSALES_NOMBRES = {};

  const el = {
    login: document.getElementById('admin-login'),
    panel: document.getElementById('admin-panel'),
    sesion: document.getElementById('admin-sesion'),
    sesionEmail: document.getElementById('admin-sesion-email'),
    formLogin: document.getElementById('form-login'),
    emailWrap: document.getElementById('admin-email-wrap'),
    emailInput: document.getElementById('admin-email'),
    passwordInput: document.getElementById('admin-password'),
    btnLogin: document.getElementById('btn-login'),
    loginEstado: document.getElementById('login-estado'),
    btnLogout: document.getElementById('btn-logout'),
    configPendiente: document.getElementById('admin-config-pendiente'),
    btnGuardar: document.getElementById('btn-guardar'),
    btnRecargar: document.getElementById('btn-recargar'),
    btnExportar: document.getElementById('btn-exportar'),
    estado: document.getElementById('admin-estado'),
    aviso: document.getElementById('admin-aviso'),
    btnNuevaCategoria: document.getElementById('btn-nueva-categoria'),
    listaCategorias: document.getElementById('lista-categorias'),
    sinCategoria: document.getElementById('admin-sin-categoria'),
    detalle: document.getElementById('admin-categoria-detalle'),
    detalleFoto: document.getElementById('detalle-categoria-foto'),
    detalleNombre: document.getElementById('detalle-categoria-nombre'),
    detalleMeta: document.getElementById('detalle-categoria-meta'),
    btnEditarCategoria: document.getElementById('btn-editar-categoria'),
    btnNuevoProducto: document.getElementById('btn-nuevo-producto'),
    categoriaVacia: document.getElementById('admin-categoria-vacia'),
    btnVacioNuevoProducto: document.getElementById('btn-vacio-nuevo-producto'),
    listaProductos: document.getElementById('lista-productos'),
    panelNuevoProducto: document.getElementById('panel-nuevo-producto'),
    productoCategoriaChip: document.getElementById('producto-categoria-chip'),
    btnCerrarFormProducto: document.getElementById('btn-cerrar-form-producto'),
    formProducto: document.getElementById('form-producto'),
    productoNombre: document.getElementById('producto-nombre'),
    productoDescripcion: document.getElementById('producto-descripcion'),
    productoFotoPreview: document.getElementById('producto-foto-preview'),
    productoFotoZona: document.getElementById('producto-foto-zona'),
    btnSubirProducto: document.getElementById('btn-subir-producto'),
    productoFotoFile: document.getElementById('producto-foto-file'),
    productoFotoEstado: document.getElementById('producto-foto-estado'),
    productoDelivery: document.getElementById('producto-delivery'),
    productoMesa: document.getElementById('producto-mesa'),
    productoDeliveryOferta: document.getElementById('producto-delivery-oferta'),
    productoMesaOferta: document.getElementById('producto-mesa-oferta'),
    productoTipoOferta: document.getElementById('producto-tipo-oferta'),
    productoOfertaFechaCampo: document.getElementById('producto-oferta-fecha-campo'),
    productoOfertaHasta: document.getElementById('producto-oferta-hasta'),
    productoAgotado: document.getElementById('producto-agotado'),
    productoAgotadoPermanente: document.getElementById('producto-agotado-permanente'),
    btnAgregarProducto: document.getElementById('btn-agregar-producto'),
    btnCancelarProducto: document.getElementById('btn-cancelar-producto'),
    productoEstado: document.getElementById('producto-estado'),
    modalCategoria: document.getElementById('modal-categoria'),
    modalCategoriaTitulo: document.getElementById('modal-categoria-titulo'),
    btnCerrarModalCategoria: document.getElementById('btn-cerrar-modal-categoria'),
    formCategoria: document.getElementById('form-categoria'),
    categoriaNombre: document.getElementById('categoria-nombre'),
    categoriaFotoPreview: document.getElementById('categoria-foto-preview'),
    categoriaFotoZona: document.getElementById('categoria-foto-zona'),
    btnSubirCategoria: document.getElementById('btn-subir-categoria'),
    categoriaFotoFile: document.getElementById('categoria-foto-file'),
    categoriaFotoEstado: document.getElementById('categoria-foto-estado'),
    categoriaEstado: document.getElementById('categoria-estado'),
    btnGuardarCategoria: document.getElementById('btn-guardar-categoria'),
    btnCancelarCategoria: document.getElementById('btn-cancelar-categoria'),
    tabsVista: document.querySelectorAll('[data-admin-vista]'),
    vistaCarta: document.getElementById('admin-vista-carta'),
    vistaPedidos: document.getElementById('admin-vista-pedidos'),
    vistaEnvios: document.getElementById('admin-vista-envios'),
    vistaFidelidad: document.getElementById('admin-vista-fidelidad'),
    btnFidelidadRecargar: document.getElementById('btn-fidelidad-recargar'),
    fidelidadEstado: document.getElementById('fidelidad-estado'),
    fidelidadAviso: document.getElementById('fidelidad-aviso'),
    formFidelidad: document.getElementById('form-fidelidad'),
    fidelidadActivo: document.getElementById('fidelidad-activo'),
    fidelidadPedidoMinimo: document.getElementById('fidelidad-pedido-minimo'),
    fidelidadCiclo: document.getElementById('fidelidad-ciclo'),
    fidelidadNiveles: document.getElementById('fidelidad-niveles'),
    btnFidelidadAgregarNivel: document.getElementById('btn-fidelidad-agregar-nivel'),
    fidelidadFormEstado: document.getElementById('fidelidad-form-estado'),
    btnGuardarFidelidad: document.getElementById('btn-guardar-fidelidad'),
    fidelidadStats: document.getElementById('fidelidad-stats'),
    fidelidadStatsEstado: document.getElementById('fidelidad-stats-estado'),
    vistaCupones: document.getElementById('admin-vista-cupones'),
    btnNuevoCupon: document.getElementById('btn-nuevo-cupon'),
    btnCuponesRecargar: document.getElementById('btn-cupones-recargar'),
    cuponesEstado: document.getElementById('cupones-estado'),
    cuponesAviso: document.getElementById('cupones-aviso'),
    cuponesLista: document.getElementById('cupones-lista'),
    formCupon: document.getElementById('form-cupon'),
    cuponId: document.getElementById('cupon-id'),
    cuponCodigo: document.getElementById('cupon-codigo'),
    cuponTipo: document.getElementById('cupon-tipo'),
    cuponValor: document.getElementById('cupon-valor'),
    cuponValorEtiqueta: document.getElementById('cupon-valor-etiqueta'),
    cuponCompraMinima: document.getElementById('cupon-compra-minima'),
    cuponFechaInicio: document.getElementById('cupon-fecha-inicio'),
    cuponFechaVencimiento: document.getElementById('cupon-fecha-vencimiento'),
    cuponUsosTotal: document.getElementById('cupon-usos-total'),
    cuponUsosCliente: document.getElementById('cupon-usos-cliente'),
    cuponSucursales: document.getElementById('cupon-sucursales'),
    cuponModalidades: document.getElementById('cupon-modalidades'),
    cuponActivo: document.getElementById('cupon-activo'),
    cuponPrimeraCompra: document.getElementById('cupon-primera-compra'),
    cuponAcumulable: document.getElementById('cupon-acumulable'),
    cuponNotaUsos: document.getElementById('cupon-nota-usos'),
    cuponFormEstado: document.getElementById('cupon-form-estado'),
    btnGuardarCupon: document.getElementById('btn-guardar-cupon'),
    btnCancelarCupon: document.getElementById('btn-cancelar-cupon'),
    btnCancelarCuponArriba: document.getElementById('btn-cancelar-cupon-arriba'),
    btnCerrarCupon: document.getElementById('btn-cerrar-cupon'),
    cuponFormTitulo: document.getElementById('cupon-form-titulo'),
    enviosAyuda: document.getElementById('envios-ayuda'),
    btnEnviosRecargar: document.getElementById('btn-envios-recargar'),
    enviosEstado: document.getElementById('envios-estado'),
    enviosAviso: document.getElementById('envios-aviso'),
    formConfigEnvios: document.getElementById('form-config-envios'),
    enviosMetrosCuadra: document.getElementById('envios-metros-cuadra'),
    enviosTiempoEstimado: document.getElementById('envios-tiempo-estimado'),
    enviosDescuentoEfectivo: document.getElementById('envios-descuento-efectivo'),
    enviosDescuentoTransferencia: document.getElementById('envios-descuento-transferencia'),
    btnGuardarConfigEnvios: document.getElementById('btn-guardar-config-envios'),
    zonasNormalesLista: document.getElementById('zonas-normales-lista'),
    zonasNormalesEstado: document.getElementById('zonas-normales-estado'),
    btnNuevoTramo: document.getElementById('btn-nuevo-tramo'),
    formTramo: document.getElementById('form-tramo'),
    tramoId: document.getElementById('tramo-id'),
    tramoSucursal: document.getElementById('tramo-sucursal'),
    tramoDesde: document.getElementById('tramo-desde'),
    tramoHasta: document.getElementById('tramo-hasta'),
    tramoCosto: document.getElementById('tramo-costo'),
    tramoActiva: document.getElementById('tramo-activa'),
    tramoEstado: document.getElementById('tramo-estado'),
    btnGuardarTramo: document.getElementById('btn-guardar-tramo'),
    btnCancelarTramo: document.getElementById('btn-cancelar-tramo'),
    tramosEstado: document.getElementById('tramos-estado'),
    tramosLista: document.getElementById('tramos-lista'),
    tramosMetrosReferencia: document.getElementById('tramos-metros-referencia'),
    pedidosBadge: document.getElementById('pedidos-badge'),
    btnPedidosActivarSonido: document.getElementById('btn-pedidos-activar-sonido'),
    pedidosVolumen: document.getElementById('pedidos-volumen'),
    pedidosSonidoEstado: document.getElementById('pedidos-sonido-estado'),
    btnPedidosActualizar: document.getElementById('btn-pedidos-actualizar'),
    pedidosEstado: document.getElementById('pedidos-estado'),
    pedidosAviso: document.getElementById('pedidos-aviso'),
    agotadosSucursalCampo: document.getElementById('agotados-sucursal-campo'),
    agotadosSucursal: document.getElementById('agotados-sucursal'),
    agotadosEstado: document.getElementById('agotados-estado'),
    agotadosAviso: document.getElementById('agotados-aviso'),
    agotadosLista: document.getElementById('agotados-lista'),
    agotadosResumen: document.getElementById('agotados-resumen'),
    agotadosFiltroEstado: document.getElementById('agotados-filtro-estado'),
    agotadosBuscar: document.getElementById('agotados-buscar'),
    agotadosCategoria: document.getElementById('agotados-categoria'),
    pedidosFiltroPeriodo: document.getElementById('pedidos-filtro-periodo'),
    pedidosPeriodoEtiqueta: document.getElementById('pedidos-periodo-etiqueta'),
    btnPedidosAnterior: document.getElementById('btn-pedidos-anterior'),
    btnPedidosSiguiente: document.getElementById('btn-pedidos-siguiente'),
    pedidosRango: document.getElementById('pedidos-rango'),
    pedidosFiltroDesde: document.getElementById('pedidos-filtro-desde'),
    pedidosFiltroHasta: document.getElementById('pedidos-filtro-hasta'),
    pedidosFiltroSucursal: document.getElementById('pedidos-filtro-sucursal'),
    pedidosVistaBtns: document.querySelectorAll('[data-pedidos-vista]'),
    pedidosModalidadBtns: document.querySelectorAll('[data-pedidos-modalidad]'),
    btnPedidosExportar: document.getElementById('btn-pedidos-exportar'),
    pedidosContenedor: document.getElementById('pedidos-contenedor'),
    pedidosTablero: document.getElementById('pedidos-tablero'),
    pedidosLista: document.getElementById('pedidos-lista'),
    pedidoTicket: document.getElementById('pedido-ticket'),
    modalPedido: document.getElementById('modal-pedido'),
    modalPedidoTitulo: document.getElementById('modal-pedido-titulo'),
    btnCerrarModalPedido: document.getElementById('btn-cerrar-modal-pedido'),
    pedidoDetalleContenido: document.getElementById('pedido-detalle-contenido')
  };

  let config = null;
  let cliente = null;
  let carta = null;
  let categoriaActivaId = null;
  let cambiosPendientes = false;
  let publicacionLocalRiesgosa = false;
  let guardando = false;
  let subidasPendientes = 0;
  let productosExpandidos = new Set();
  const previewsTemporales = new Set();
  const tokensUploadProducto = new Map();

  let adminRol = 'dueno';
  let adminSucursalId = null;
  let adminRolError = false;

  let pedidos = [];
  let pedidosCargados = false;
  let pedidosCargando = false;
  let pedidoAbiertoId = null;
  let pedidosCanal = null;
  let pedidosTimer = null;
  let pedidosSonidoActivo = true;
  let pedidosVolumen = 0.7;
  let pedidosAlertaTimer = null;
  let pedidosTituloTimer = null;
  let pedidosTituloAlternado = false;
  let pedidosTituloOriginal = document.title;
  let audioContexto = null;
  let audioDesbloqueado = false;
  let pedidosVista = 'tablero';
  let pedidosModalidad = '';
  let pedidosPeriodo = 'dia';
  let pedidosFechaDia = '';
  let pedidosSoportaPagos = true;

  let agotadosCargados = false;
  let agotadosCargando = false;
  // Fuente única en memoria: sucursal_id -> Set(producto_id). La usan Pedidos y la carta.
  let agotadosPorSucursal = new Map();
  let agotadosFiltroEstado = 'no-disponibles';
  const agotadosSaliendo = new Set();
  let agotadosAvisoTimer = null;
  const agotadosGuardando = new Set();
  let agotadosCanal = null;
  let agotadosRealtimeTimer = null;

  let enviosCargados = false;
  let cuponesLista = [];
  let cuponesUsos = [];
  let cuponesCargados = false;
  let cuponesCargando = false;
  let fidelidadCargada = false;
  let fidelidadCargando = false;
  let fidelidadConfigGuardada = null;
  let enviosCargando = false;
  let tramosEnvios = [];
  let zonasNormales = [];
  let configEnvios = { metrosPorCuadra: 100, tiempoEstimado: null, descuentos: { efectivo: 0, transferencia: 0 } };

  let modalCategoriaModo = 'crear';
  let categoriaEditandoId = null;
  let fotoCategoriaSeleccionada = '';
  let subiendoCategoria = false;
  let tokenUploadCategoria = 0;

  let fotoNuevaProductoUrl = '';
  let subiendoFotoNueva = false;
  let tokenUploadNuevo = 0;

  function escaparHtml(valor) {
    return String(valor === undefined || valor === null ? '' : valor)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function formatearPrecio(valor) {
    const numero = Number(valor);
    if (!Number.isFinite(numero)) return '$0';
    try {
      return new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS', maximumFractionDigits: 0 }).format(numero);
    } catch (error) {
      return `$${numero}`;
    }
  }

  const MAPA_CATEGORIAS_LEGACY = {
    promos: 'promo',
    hamburguesas: 'burger',
    pizzas: 'pizza',
    lomitos: 'lomo',
    milanesas: 'milanesa',
    barrolucos: 'barroluco',
    bebidas: 'bebida'
  };

  function normalizarCarta(contenido) {
    const categoriasFuente = Array.isArray(contenido && contenido.categorias) ? contenido.categorias : [];
    const productos = Array.isArray(contenido && contenido.productos) ? contenido.productos : [];
    const mapa = new Map();
    const usados = new Set();
    const categorias = [];

    categoriasFuente.forEach(cat => {
      if (!cat) return;
      const idAnterior = String(cat.id || '').trim();
      if (!idAnterior) return;
      const idNuevo = MAPA_CATEGORIAS_LEGACY[idAnterior] || idAnterior;
      mapa.set(idAnterior, idNuevo);
      if (usados.has(idNuevo)) return;
      usados.add(idNuevo);
      cat.id = idNuevo;
      categorias.push(cat);
    });

    productos.forEach(producto => {
      if (!producto) return;
      const categoriaAnterior = String(producto.categoria || '').trim();
      producto.categoria = mapa.get(categoriaAnterior)
        || MAPA_CATEGORIAS_LEGACY[categoriaAnterior]
        || categoriaAnterior;
    });

    return { categorias, productos };
  }

  function asegurarCategoriaPromos() {
    if (!carta) return;
    if (!Array.isArray(carta.categorias)) carta.categorias = [];
    const existe = carta.categorias.some(cat => cat && cat.id === 'promo');
    if (!existe) {
      carta.categorias.unshift({
        id: 'promo',
        nombre: 'PROMOS',
        foto: 'assets/categoria-delivery.webp'
      });
    }
  }

  function categoriaPorId(id) {
    if (!carta) return null;
    return carta.categorias.find(cat => cat && cat.id === id) || null;
  }

  function categoriaValida(id) {
    return !!categoriaPorId(id);
  }

  function nombreCategoria(id) {
    const cat = categoriaPorId(id);
    return cat ? cat.nombre : (id || 'Sin categoría');
  }

  function esRutaImagenSegura(valor) {
    return PM.esRutaImagenSegura(valor);
  }

  function rutaImagenCategoria(cat) {
    const foto = cat && typeof cat.foto === 'string' ? cat.foto.trim() : '';
    return esRutaImagenSegura(foto) ? foto : 'assets/logo.webp';
  }

  function rutaImagenProducto(producto) {
    const foto = producto && typeof producto.foto === 'string' ? producto.foto.trim() : '';
    if (esRutaImagenSegura(foto)) return foto;
    const cat = categoriaPorId(producto && producto.categoria);
    return cat ? rutaImagenCategoria(cat) : 'assets/logo.webp';
  }

  const TIPOS_OFERTA = ['dia', 'semana', 'fecha'];

  function tipoOfertaProducto(producto) {
    const tipo = producto && producto.tipoOferta;
    if (tipo === 'semana') return 'semana';
    if (tipo === 'fecha') return 'fecha';
    return 'dia';
  }

  function etiquetaTipoOferta(tipo) {
    if (tipo === 'semana') return 'Oferta de la semana';
    if (tipo === 'fecha') return 'Hasta una fecha';
    return 'Oferta del día';
  }

  function precioOfertaValido(producto) {
    if (!producto) return false;
    const valido = valor => Number.isFinite(Number(valor)) && Number(valor) > 0;
    return valido(producto.delivery_oferta) || valido(producto.mesa_oferta);
  }

  function estadoOfertaProducto(producto) {
    if (!precioOfertaValido(producto)) {
      return { tiene: false, vencida: false, texto: '' };
    }

    const tipo = tipoOfertaProducto(producto);
    const hasta = PM.parseFechaOferta(producto.oferta_hasta);

    if (tipo === 'fecha' && hasta !== null) {
      if (Date.now() > hasta) {
        return { tiene: true, vencida: true, texto: `Vencida (${PM.fechaOfertaCorta(producto.oferta_hasta)})` };
      }
      return { tiene: true, vencida: false, texto: `Hasta el ${PM.fechaOfertaCorta(producto.oferta_hasta)}` };
    }

    return { tiene: true, vencida: false, texto: '' };
  }

  function isoDesdeFechaInput(valor) {
    const texto = String(valor || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(texto)) return '';
    return `${texto}T23:59:00-03:00`;
  }

  function fechaInputDesdeIso(valorIso) {
    const paraInput = PM.fechaOfertaParaInput(valorIso);
    return paraInput ? paraInput.slice(0, 10) : '';
  }

  function productosDeCategoria(id) {
    if (!carta || !Array.isArray(carta.productos)) return [];
    return carta.productos.filter(prod => prod && prod.categoria === id);
  }

  function contarOfertas(productos) {
    return productos.filter(prod => precioOfertaValido(prod) && PM.ofertaVigente(prod)).length;
  }

  function opcionesCategorias(seleccionada) {
    if (!carta) return '';
    return carta.categorias
      .filter(cat => cat && cat.id)
      .map(cat => `<option value="${escaparHtml(cat.id)}"${cat.id === seleccionada ? ' selected' : ''}>${escaparHtml(cat.nombre || cat.id)}</option>`)
      .join('');
  }

  function mostrarEstado(elemento, texto, tipo = '') {
    if (!elemento) return;
    elemento.textContent = texto || '';
    if (tipo) elemento.dataset.tipo = tipo;
    else elemento.removeAttribute('data-tipo');
  }

  function mostrarAviso(texto, tipo = 'info') {
    if (!el.aviso) return;
    if (!texto) {
      el.aviso.hidden = true;
      el.aviso.textContent = '';
      return;
    }
    el.aviso.hidden = false;
    el.aviso.dataset.tipo = tipo;
    el.aviso.textContent = texto;
  }

  function esAdminSucursal() {
    return adminRol === 'sucursal';
  }

  function puedeEditarFilaSucursal(sucursalId) {
    if (adminRol === 'dueno') return true;
    return !!adminSucursalId && String(sucursalId || '') === String(adminSucursalId);
  }

  function pedidoVisiblePorRol(pedido) {
    if (!esAdminSucursal()) return true;
    return !!adminSucursalId && String(pedido && pedido.sucursal_id) === String(adminSucursalId);
  }

  function sucursalVisibleParaRol(sucursalId) {
    if (adminRol === 'dueno') return true;
    if (!adminSucursalId) return false;
    return !sucursalId || String(sucursalId) === String(adminSucursalId);
  }

  function aplicarAvisoRol() {
    if (!adminRolError) return;
    const texto = 'No se pudo verificar tu rol, recargá la página.';
    if (el.pedidosAviso) {
      el.pedidosAviso.hidden = false;
      el.pedidosAviso.dataset.tipo = 'error';
      el.pedidosAviso.textContent = texto;
    }
    if (el.enviosAviso) {
      el.enviosAviso.hidden = false;
      el.enviosAviso.dataset.tipo = 'error';
      el.enviosAviso.textContent = texto;
    }
  }

  function crearPreviewTemporal(archivo) {
    if (!archivo || typeof URL === 'undefined' || typeof URL.createObjectURL !== 'function') return '';
    try {
      const url = URL.createObjectURL(archivo);
      previewsTemporales.add(url);
      return url;
    } catch (error) {
      return '';
    }
  }

  function revocarPreviewTemporal(url) {
    if (!url || !previewsTemporales.has(url)) return;
    previewsTemporales.delete(url);
    try { URL.revokeObjectURL(url); } catch (error) {}
  }

  function aplicarPreviewImagen(imagen, url) {
    if (!imagen || !url) return;
    imagen.dataset.fallback = '';
    imagen.src = url;
  }

  function marcarCambios() {
    cambiosPendientes = true;
    mostrarEstado(el.estado, 'Cambios sin guardar', 'pendiente');
  }

  function actualizarBotonGuardar() {
    if (!el.btnGuardar) return;
    const bloqueado = guardando || subidasPendientes > 0;
    el.btnGuardar.disabled = bloqueado;
    if (guardando) el.btnGuardar.textContent = 'Guardando...';
    else if (subidasPendientes > 0) el.btnGuardar.textContent = 'Subiendo imágenes...';
    else el.btnGuardar.textContent = 'Guardar y publicar';
  }

  function actualizarBotonAgregar() {
    if (!el.btnAgregarProducto) return;
    el.btnAgregarProducto.disabled = subiendoFotoNueva;
    el.btnAgregarProducto.textContent = subiendoFotoNueva ? 'Subiendo imagen...' : 'Agregar producto';
  }

  function actualizarBotonGuardarCategoria() {
    if (!el.btnGuardarCategoria) return;
    el.btnGuardarCategoria.disabled = subiendoCategoria;
    el.btnGuardarCategoria.textContent = subiendoCategoria ? 'Subiendo imagen...' : 'Guardar categoría';
  }

  function configValida() {
    return !!(config && config.supabaseUrl && config.supabaseAnonKey);
  }

  function tablaCarta() {
    return (config && config.tabla) || 'carta';
  }

  function filaCarta() {
    return config && config.filaId !== undefined ? config.filaId : 1;
  }

  async function cargarConfig() {
    try {
      const resp = await fetch(RUTA_CONFIG, { cache: 'no-store' });
      if (!resp.ok) throw new Error('No se pudo leer data/nube.json');
      config = await resp.json();
    } catch (error) {
      config = null;
      console.warn(error.message);
    }
  }

  async function cargarSucursalesConfig() {
    try {
      const resp = await fetch('data/sucursales.json', { cache: 'no-store' });
      if (!resp.ok) throw new Error('No se pudo leer data/sucursales.json');
      const datos = await resp.json();
      const ids = Array.isArray(datos.sucursales)
        ? datos.sucursales.map(sucursal => String(sucursal.id || '').trim()).filter(Boolean)
        : [];
      if (ids.length > 0) SUCURSALES_POR_DEFECTO = ids;
      SUCURSALES_NOMBRES = {};
      if (Array.isArray(datos.sucursales)) {
        datos.sucursales.forEach(sucursal => {
          if (!sucursal || !sucursal.id) return;
          const id = String(sucursal.id).trim();
          SUCURSALES_NOMBRES[id] = String(sucursal.nombre || sucursal.tituloCarta || id).trim();
        });
      }
    } catch (error) {
      console.warn(error.message);
    }
    SUCURSALES_POR_DEFECTO.forEach(id => {
      if (!SUCURSALES_NOMBRES[id]) SUCURSALES_NOMBRES[id] = id;
    });
    poblarFiltroSucursalesPedidos();
    poblarSelectSucursalesEnvios();
    poblarSelectAgotados();
  }

  function inicializarCliente() {
    if (!configValida()) return null;
    if (!window.supabase || typeof window.supabase.createClient !== 'function') return null;

    cliente = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false
      }
    });

    return cliente;
  }

  function mostrarLogin() {
    adminRol = 'dueno';
    adminSucursalId = null;
    adminRolError = false;
    if (el.login) el.login.hidden = false;
    if (el.panel) el.panel.hidden = true;
    if (el.sesion) el.sesion.hidden = true;
    if (el.passwordInput) el.passwordInput.value = '';
    cerrarModalCategoria();
    cerrarModalPedido();
    cerrarFormTramo();
    detenerRealtimePedidos();
    detenerRealtimeAgotados();
    detenerAlertaPedidos();
    enviosCargados = false;
    agotadosCargados = false;
    agotadosPorSucursal = new Map();
    actualizarBotonGuardar();
  }

  async function mostrarPanel(usuario) {
    if (!usuario) return;

    try {
      const { data: esAdmin, error } = await cliente.rpc('es_admin');
      if (error) throw error;
      if (esAdmin !== true) {
        mostrarEstado(el.loginEstado, 'Este usuario no tiene permisos de administrador.', 'error');
        mostrarLogin();
        if (cliente) await cliente.auth.signOut();
        return;
      }
    } catch (error) {
      const detalle = error && error.message ? error.message : 'No se pudo verificar el permiso.';
      mostrarEstado(el.loginEstado, `No se pudo verificar el permiso de administrador: ${detalle}`, 'error');
      mostrarLogin();
      if (cliente) await cliente.auth.signOut();
      return;
    }

    adminRol = 'sucursal';
    adminSucursalId = null;
    adminRolError = false;
    try {
      const { data, error } = await cliente.rpc('mi_rol');
      if (error) throw error;
      if (!data || !data.rol) throw new Error('Rol vacío');
      adminRol = data.rol === 'dueno' ? 'dueno' : 'sucursal';
      adminSucursalId = data.sucursal_id ? String(data.sucursal_id) : null;
      adminRolError = false;
    } catch (error) {
      adminRol = 'sucursal';
      adminSucursalId = null;
      adminRolError = true;
      console.warn('No se pudo verificar el rol del administrador:', error.message || error);
    }

    const yaVisible = el.panel && !el.panel.hidden;

    if (el.login) el.login.hidden = true;
    if (el.panel) el.panel.hidden = false;
    if (el.sesion) el.sesion.hidden = false;
    if (el.sesionEmail) el.sesionEmail.textContent = usuario.email || 'Administrador';

    if (!yaVisible) {
      await cargarCarta();
      cargarAgotados({ silencioso: true });
      await cargarPedidos({ silencioso: true });
      iniciarRealtimePedidos();
      iniciarRealtimeAgotados();
      iniciarRefrescoPedidos();
    }

    aplicarPermisosRol();
  }

  function aplicarPermisosRol() {
    const restringido = esAdminSucursal();

    el.tabsVista.forEach(tab => {
      if (tab.dataset.adminVista === 'carta') tab.hidden = restringido;
      if (tab.dataset.adminVista === 'cupones') tab.hidden = !puedeVerCupones();
      if (tab.dataset.adminVista === 'fidelidad') tab.hidden = !puedeVerFidelidad();
      if (tab.dataset.adminVista === 'estadisticas') tab.hidden = !puedeVerCupones();
    });

    poblarFiltroSucursalesPedidos();
    poblarSelectSucursalesEnvios();
    poblarSelectAgotados();

    if (el.formConfigEnvios) el.formConfigEnvios.hidden = restringido;
    const seccionConfig = el.formConfigEnvios ? el.formConfigEnvios.closest('.admin-card') : null;
    if (seccionConfig) seccionConfig.hidden = restringido;

    if (el.btnNuevoTramo) el.btnNuevoTramo.hidden = restringido && !adminSucursalId;
    if (restringido && !adminSucursalId) cerrarFormTramo();

    if (restringido && el.vistaCarta && !el.vistaCarta.hidden) {
      mostrarVistaAdmin('pedidos');
    }
    if (!puedeVerCupones() && el.vistaCupones && !el.vistaCupones.hidden) {
      mostrarVistaAdmin('pedidos');
    }
    if (!puedeVerFidelidad() && el.vistaFidelidad && !el.vistaFidelidad.hidden) {
      mostrarVistaAdmin('pedidos');
    }
    const vistaStatsPerm = document.getElementById('admin-vista-estadisticas');
    if (!puedeVerCupones() && vistaStatsPerm && !vistaStatsPerm.hidden) {
      mostrarVistaAdmin('pedidos');
    }

    if (enviosCargados) {
      renderConfigEnvios();
      renderZonasNormales();
      renderTramosEnvios();
    }

    if (adminRolError) aplicarAvisoRol();
  }

  async function cargarCarta() {
    if (!cliente) return;
    mostrarAviso('');
    mostrarEstado(el.estado, 'Cargando carta...');

    let contenido = null;
    let desdeNube = false;
    let errorNube = null;

    try {
      const { data, error } = await cliente
        .from(tablaCarta())
        .select('contenido')
        .eq('id', filaCarta())
        .maybeSingle();

      if (error) throw error;
      if (data && data.contenido) {
        contenido = data.contenido;
        desdeNube = true;
      }
    } catch (error) {
      errorNube = error;
      console.warn('No se pudo leer la carta desde Supabase:', error.message || error);
    }

    if (!contenido) {
      try {
        const resp = await fetch(RUTA_CARTA_LOCAL, { cache: 'no-store' });
        if (!resp.ok) throw new Error('No se pudo leer data/cartas.json');
        contenido = await resp.json();
      } catch (error) {
        mostrarEstado(el.estado, 'No se pudo cargar la carta local', 'error');
        mostrarAviso('Revisá data/cartas.json y la configuración de Supabase.', 'error');
        return;
      }
    }

    const activaAnterior = categoriaActivaId;
    carta = normalizarCarta(contenido);
    asegurarCategoriaPromos();
    categoriaActivaId = categoriaValida(activaAnterior)
      ? activaAnterior
      : (categoriaValida('promo') ? 'promo' : (carta.categorias[0] ? carta.categorias[0].id : null));
    publicacionLocalRiesgosa = !!errorNube;
    productosExpandidos.clear();
    cambiosPendientes = false;
    cerrarFormularioProducto();
    cerrarModalCategoria();
    renderizarTodo();

    if (desdeNube) {
      mostrarEstado(el.estado, 'Carta sincronizada con la nube', 'ok');
      mostrarAviso('');
    } else {
      mostrarEstado(el.estado, 'Carta local cargada', 'pendiente');
      const detalle = errorNube
        ? `No se pudo leer Supabase (${errorNube.message || 'error de conexión'}). Se cargó la copia local.`
        : 'La nube todavía no tiene contenido. Se cargó la copia local.';
      mostrarAviso(`${detalle} Guardá para publicar esta carta en la nube.`, 'info');
    }
  }

  function renderizarTodo() {
    renderizarCategorias();
    renderizarDetalleCategoria();
    actualizarBotonGuardar();
    actualizarBotonAgregar();
    actualizarBotonGuardarCategoria();
  }

  function renderizarCategorias() {
    if (!el.listaCategorias || !carta) return;

    if (!carta.categorias.length) {
      el.listaCategorias.innerHTML = '<p class="admin-vacio">Todavía no hay categorías. Creá la primera para empezar.</p>';
      return;
    }

    el.listaCategorias.innerHTML = carta.categorias.map(cat => {
      if (!cat || !cat.id) return '';
      const productos = productosDeCategoria(cat.id);
      const ofertas = contarOfertas(productos);
      const activa = cat.id === categoriaActivaId;

      return `
        <article class="admin-cat-card${activa ? ' activa' : ''}" data-id="${escaparHtml(cat.id)}">
          <button type="button" class="admin-cat-open" data-accion="seleccionar-categoria" data-id="${escaparHtml(cat.id)}" aria-pressed="${activa ? 'true' : 'false'}">
            <img class="admin-cat-foto" src="${escaparHtml(rutaImagenCategoria(cat))}" alt="" loading="lazy" decoding="async">
            <span class="admin-cat-sombra"></span>
            <span class="admin-cat-contenido">
              <span class="admin-cat-nombre">${escaparHtml(cat.nombre || cat.id)}</span>
              <span class="admin-cat-meta">${productos.length} producto${productos.length === 1 ? '' : 's'}</span>
            </span>
            ${ofertas > 0 ? `<span class="admin-cat-ofertas">${ofertas} en oferta</span>` : ''}
          </button>
          <button type="button" class="admin-cat-editar" data-accion="editar-categoria" data-id="${escaparHtml(cat.id)}">Editar</button>
        </article>
      `;
    }).join('');
  }

  function seleccionarCategoria(id, hacerScroll = false) {
    if (!categoriaValida(id)) return;
    if (categoriaActivaId !== id) {
      categoriaActivaId = id;
      productosExpandidos.clear();
      cerrarFormularioProducto();
    }
    renderizarTodo();
    if (hacerScroll && el.detalle && typeof el.detalle.scrollIntoView === 'function') {
      requestAnimationFrame(() => {
        el.detalle.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    }
  }

  function renderizarDetalleCategoria() {
    if (!el.detalle) return;
    const cat = categoriaPorId(categoriaActivaId);

    if (!cat) {
      el.detalle.hidden = true;
      if (el.sinCategoria) el.sinCategoria.hidden = false;
      if (el.listaProductos) el.listaProductos.innerHTML = '';
      return;
    }

    if (el.sinCategoria) el.sinCategoria.hidden = true;
    el.detalle.hidden = false;

    const productos = productosDeCategoria(cat.id);
    const ofertas = contarOfertas(productos);

    if (el.detalleFoto) {
      el.detalleFoto.dataset.fallback = '';
      el.detalleFoto.src = rutaImagenCategoria(cat);
    }
    if (el.detalleNombre) el.detalleNombre.textContent = cat.nombre || cat.id;
    if (el.detalleMeta) {
      el.detalleMeta.textContent = `${productos.length} producto${productos.length === 1 ? '' : 's'}${ofertas > 0 ? ` · ${ofertas} en oferta` : ''}`;
    }

    renderizarProductos(productos);
  }

  function renderizarProductos(productos) {
    if (!el.listaProductos) return;

    if (!productos.length) {
      el.listaProductos.innerHTML = '';
      if (el.categoriaVacia) el.categoriaVacia.hidden = false;
      return;
    }

    if (el.categoriaVacia) el.categoriaVacia.hidden = true;

    el.listaProductos.innerHTML = productos.map(producto => {
      const id = producto.id;
      const abierto = productosExpandidos.has(id);
      const tipo = tipoOfertaProducto(producto);
      const oferta = estadoOfertaProducto(producto);
      const precios = producto.precios || {};
      const agotado = PM.productoEstaAgotado(producto);
      const agotadoPermanente = producto.agotado_hasta_nuevo_aviso === true;
      const ofertaBadge = oferta.tiene
        ? (oferta.vencida
          ? '<span class="admin-badge admin-badge-oferta-vencida">OFERTA VENCIDA</span>'
          : `<span class="admin-badge admin-badge-${tipo}">${etiquetaTipoOferta(tipo)}</span>`)
        : '';
      const agotadoBadge = agotado
        ? `<span class="admin-badge admin-badge-agotado">${agotadoPermanente ? 'AGOTADO PERMANENTE' : 'AGOTADO HOY'}</span>`
        : '';
      const ofertaFechas = oferta.tiene && oferta.texto
        ? `<p class="admin-prod-desc admin-prod-oferta-fechas">${escaparHtml(oferta.texto)}</p>`
        : '';

      return `
        <article class="admin-producto${abierto ? ' abierto' : ''}" data-id="${escaparHtml(id)}" data-oferta="${oferta.tiene ? (oferta.vencida ? 'vencida' : 'activa') : 'ninguna'}">
          <div class="admin-prod-resumen">
            <img class="admin-prod-thumb" src="${escaparHtml(rutaImagenProducto(producto))}" alt="" loading="lazy" decoding="async">
            <div class="admin-prod-info">
              <div class="admin-prod-titulo-fila">
                <h3 class="admin-prod-nombre">${escaparHtml(producto.nombre || id)}</h3>
                ${ofertaBadge}
                ${agotadoBadge}
              </div>
              <p class="admin-prod-desc">${escaparHtml(producto.descripcion || 'Sin descripción')}</p>
              <p class="admin-prod-precios">Delivery ${formatearPrecio(precios.delivery)} · Mesa ${formatearPrecio(precios.mesa)}</p>
              ${ofertaFechas}
            </div>
            <div class="admin-prod-acciones">
              <button type="button" class="btn-secundario" data-accion="toggle-producto" data-id="${escaparHtml(id)}" aria-expanded="${abierto ? 'true' : 'false'}">${abierto ? 'Cerrar' : 'Editar'}</button>
              <button type="button" class="btn-peligro" data-accion="eliminar-producto" data-id="${escaparHtml(id)}">Eliminar</button>
            </div>
          </div>

          <div class="admin-prod-disponibilidad" data-disponibilidad="${escaparHtml(id)}">${htmlDisponibilidadProducto(producto)}</div>

          <div class="admin-prod-editor" ${abierto ? '' : 'hidden'}>
            <div class="admin-grid-campos">
              <label class="admin-campo admin-campo-nombre">
                <span>Nombre</span>
                <input type="text" data-campo-producto="nombre" value="${escaparHtml(producto.nombre || '')}">
              </label>

              <label class="admin-campo admin-campo-categoria">
                <span>Categoría</span>
                <select data-campo-producto="categoria">
                  ${opcionesCategorias(producto.categoria)}
                </select>
              </label>

              <label class="admin-campo admin-campo-descripcion">
                <span>Descripción</span>
                <textarea rows="2" data-campo-producto="descripcion">${escaparHtml(producto.descripcion || '')}</textarea>
              </label>

              <div class="admin-campo admin-campo-ancho">
                <span>Imagen del producto</span>
                <div class="admin-upload admin-upload-compacta" data-upload-zona title="Hacé clic para cambiar la imagen">
                  <img class="admin-upload-preview" data-preview-producto="${escaparHtml(id)}" src="${escaparHtml(rutaImagenProducto(producto))}" alt="Vista previa">
                  <div class="admin-upload-info">
                    <button type="button" class="btn-secundario" data-accion="subir-imagen-producto" data-id="${escaparHtml(id)}">Cambiar imagen</button>
                    <input type="file" class="admin-file-input" accept="image/*" data-file-producto aria-label="Cambiar imagen del producto">
                    <p class="admin-upload-ayuda">JPG, PNG, WEBP, AVIF o GIF · máximo 5 MB</p>
                    <p class="admin-estado" data-upload-producto="${escaparHtml(id)}" aria-live="polite"></p>
                  </div>
                </div>
              </div>

              <label class="admin-campo">
                <span>Precio delivery</span>
                <input type="number" min="0" step="100" data-campo-producto="delivery" value="${escaparHtml(precios.delivery === undefined ? '' : precios.delivery)}">
              </label>

              <label class="admin-campo">
                <span>Precio mesa</span>
                <input type="number" min="0" step="100" data-campo-producto="mesa" value="${escaparHtml(precios.mesa === undefined ? '' : precios.mesa)}">
              </label>

              <label class="admin-campo">
                <span>Tipo de oferta</span>
                <select data-campo-producto="tipoOferta">
                  <option value="dia"${tipo === 'dia' ? ' selected' : ''}>Oferta del día</option>
                  <option value="semana"${tipo === 'semana' ? ' selected' : ''}>Oferta de la semana</option>
                  <option value="fecha"${tipo === 'fecha' ? ' selected' : ''}>Hasta una fecha</option>
                </select>
              </label>

              <label class="admin-campo">
                <span>Delivery oferta</span>
                <input type="number" min="0" step="100" data-campo-producto="delivery_oferta" value="${escaparHtml(producto.delivery_oferta === undefined ? '' : producto.delivery_oferta)}">
              </label>

              <label class="admin-campo">
                <span>Mesa oferta</span>
                <input type="number" min="0" step="100" data-campo-producto="mesa_oferta" value="${escaparHtml(producto.mesa_oferta === undefined ? '' : producto.mesa_oferta)}">
              </label>

              <label class="admin-campo admin-campo-oferta-fecha"${tipo === 'fecha' ? '' : ' hidden'}>
                <span>Termina el</span>
                <input type="date" data-campo-producto="oferta_hasta_fecha" value="${escaparHtml(fechaInputDesdeIso(producto.oferta_hasta))}">
              </label>

              <label class="admin-campo admin-campo-check">
                <span>Agotado hoy</span>
                <input type="checkbox" data-campo-producto="agotado" ${agotado ? 'checked' : ''}>
              </label>

              <label class="admin-campo admin-campo-check">
                <span>Hasta nuevo aviso</span>
                <input type="checkbox" data-campo-producto="agotado_hasta_nuevo_aviso" ${agotadoPermanente ? 'checked' : ''}>
              </label>
            </div>
          </div>
        </article>
      `;
    }).join('');
  }

  function buscarProducto(id) {
    if (!carta) return null;
    return carta.productos.find(prod => prod && prod.id === id) || null;
  }

  function buscarTarjetaProducto(id) {
    if (!el.listaProductos) return null;
    return Array.from(el.listaProductos.querySelectorAll('.admin-producto'))
      .find(card => card.dataset.id === id) || null;
  }

  function actualizarResumenPrecios(card, producto) {
    const precios = card && card.querySelector('.admin-prod-precios');
    if (!precios || !producto) return;
    const valores = producto.precios || {};
    precios.textContent = `Delivery ${formatearPrecio(valores.delivery)} · Mesa ${formatearPrecio(valores.mesa)}`;
  }

  function actualizarResumenOferta(card, producto) {
    if (!card || !producto) return;
    const info = card.querySelector('.admin-prod-info');
    if (!info) return;

    const estado = estadoOfertaProducto(producto);
    let parrafo = info.querySelector('.admin-prod-oferta-fechas');

    if (!estado.tiene || !estado.texto) {
      if (parrafo) parrafo.remove();
      return;
    }

    if (!parrafo) {
      parrafo = document.createElement('p');
      parrafo.className = 'admin-prod-desc admin-prod-oferta-fechas';
      info.appendChild(parrafo);
    }
    parrafo.textContent = estado.texto;
  }

  function actualizarCampoProducto(control) {
    if (!control || !carta) return;
    const contenedor = control.closest('[data-id]');
    if (!contenedor) return;

    const producto = buscarProducto(contenedor.dataset.id);
    if (!producto) return;

    const campo = control.dataset.campoProducto;
    if (!campo) return;

    if (campo === 'nombre') {
      producto.nombre = control.value;
      const titulo = contenedor.querySelector('.admin-prod-nombre');
      if (titulo) titulo.textContent = control.value.trim() || producto.id;
    } else if (campo === 'descripcion') {
      producto.descripcion = control.value;
      const desc = contenedor.querySelector('.admin-prod-desc');
      if (desc) desc.textContent = control.value.trim() || 'Sin descripción';
    } else if (campo === 'categoria') {
      if (!categoriaValida(control.value)) return;

      const categoriaAnterior = producto.categoria;
      const idAnterior = producto.id;
      const sufijo = idAnterior.startsWith(`${categoriaAnterior}_`)
        ? idAnterior.slice(categoriaAnterior.length + 1)
        : idAnterior;
      const idsOcupados = new Set(
        carta.productos
          .filter(otro => otro && otro !== producto)
          .map(otro => otro.id)
      );
      const idNuevo = PM.idUnico(`${control.value}_${sufijo}`, idsOcupados);

      producto.id = idNuevo;
      producto.categoria = control.value;

      if (producto.variaciones && Array.isArray(producto.variaciones.opciones)) {
        producto.variaciones.opciones.forEach(opcion => {
          if (opcion && typeof opcion.id === 'string' && opcion.id.startsWith(idAnterior)) {
            opcion.id = idNuevo + opcion.id.slice(idAnterior.length);
          }
        });
      }

      if (Array.isArray(producto.adicionales)) {
        producto.adicionales.forEach(adicional => {
          if (adicional && typeof adicional.id === 'string' && adicional.id.startsWith(idAnterior)) {
            adicional.id = idNuevo + adicional.id.slice(idAnterior.length);
          }
        });
      }

      productosExpandidos.delete(idAnterior);
      productosExpandidos.add(idNuevo);
      tokensUploadProducto.delete(idAnterior);
      marcarCambios();
      renderizarCategorias();
      renderizarDetalleCategoria();
      return;
    } else if (campo === 'delivery' || campo === 'mesa') {
      if (!producto.precios || typeof producto.precios !== 'object') producto.precios = {};
      const valor = Number(control.value);
      if (control.value === '' || !Number.isFinite(valor) || valor < 0) delete producto.precios[campo];
      else producto.precios[campo] = valor;
      actualizarResumenPrecios(contenedor, producto);
    } else if (campo === 'tipoOferta') {
      producto.tipoOferta = TIPOS_OFERTA.includes(control.value) ? control.value : 'dia';
      if (producto.tipoOferta === 'fecha') {
        delete producto.oferta_desde;
      } else {
        delete producto.oferta_desde;
        delete producto.oferta_hasta;
      }
      marcarCambios();
      renderizarCategorias();
      renderizarDetalleCategoria();
      return;
    } else if (campo === 'oferta_hasta_fecha') {
      const valor = isoDesdeFechaInput(control.value);
      if (valor) producto.oferta_hasta = valor;
      else delete producto.oferta_hasta;
      const estado = estadoOfertaProducto(producto);
      contenedor.dataset.oferta = estado.tiene ? (estado.vencida ? 'vencida' : 'activa') : 'ninguna';
      actualizarResumenOferta(contenedor, producto);
      marcarCambios();
      return;
    } else if (campo === 'delivery_oferta' || campo === 'mesa_oferta') {
      const valor = Number(control.value);
      if (control.value === '' || !Number.isFinite(valor) || valor <= 0) delete producto[campo];
      else producto[campo] = valor;
      actualizarResumenOferta(contenedor, producto);
    } else if (campo === 'agotado') {
      const activo = !!control.checked;
      producto.agotado = activo;

      if (activo) {
        producto.agotado_fecha = PM.hoyArgentina();
      } else {
        producto.agotado_fecha = null;
        producto.agotado_hasta_nuevo_aviso = false;
      }

      productosExpandidos.add(producto.id);
      marcarCambios();
      renderizarCategorias();
      renderizarDetalleCategoria();
      return;
    } else if (campo === 'agotado_hasta_nuevo_aviso') {
      const permanente = !!control.checked;
      producto.agotado_hasta_nuevo_aviso = permanente;

      if (permanente) {
        producto.agotado = true;
        producto.agotado_fecha = producto.agotado_fecha || PM.hoyArgentina();
      } else if (producto.agotado === true && producto.agotado_fecha !== PM.hoyArgentina()) {
        producto.agotado = false;
        producto.agotado_fecha = null;
      }

      productosExpandidos.add(producto.id);
      marcarCambios();
      renderizarCategorias();
      renderizarDetalleCategoria();
      return;
    }

    marcarCambios();
  }

  function toggleProducto(id) {
    if (productosExpandidos.has(id)) productosExpandidos.delete(id);
    else productosExpandidos.add(id);

    const card = buscarTarjetaProducto(id);
    if (!card) return;
    const editor = card.querySelector('.admin-prod-editor');
    const boton = card.querySelector('[data-accion="toggle-producto"]');
    const abierto = productosExpandidos.has(id);
    card.classList.toggle('abierto', abierto);
    if (editor) editor.hidden = !abierto;
    if (boton) {
      boton.textContent = abierto ? 'Cerrar' : 'Editar';
      boton.setAttribute('aria-expanded', abierto ? 'true' : 'false');
    }
  }

  function eliminarProducto(id) {
    const producto = buscarProducto(id);
    if (!producto) return;

    const nombre = producto.nombre || producto.id;
    if (!window.confirm(`¿Eliminar "${nombre}" de la carta? El cambio se publica al guardar.`)) return;

    carta.productos = carta.productos.filter(prod => prod && prod.id !== id);
    productosExpandidos.delete(id);
    renderizarCategorias();
    renderizarDetalleCategoria();
    marcarCambios();
  }

  function validarArchivoImagen(archivo) {
    if (!archivo) throw new Error('No se seleccionó ningún archivo.');
    const tipo = String(archivo.type || '').toLowerCase();
    const extensionValida = /\.(jpe?g|png|webp|avif|gif)$/i.test(archivo.name || '');
    if (!TIPOS_IMAGEN.includes(tipo) && !extensionValida) {
      throw new Error('El archivo debe ser una imagen JPG, PNG, WEBP, AVIF o GIF.');
    }
    if (archivo.size > TAMANO_MAXIMO_IMAGEN) {
      throw new Error('La imagen supera el máximo de 5 MB.');
    }
  }

  function extensionImagen(archivo) {
    const tipo = String(archivo.type || '').toLowerCase();
    const mapa = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/avif': 'avif',
      'image/gif': 'gif'
    };
    if (mapa[tipo]) return mapa[tipo];
    const coincidencia = String(archivo.name || '').toLowerCase().match(/\.(jpe?g|png|webp|avif|gif)$/);
    return coincidencia ? coincidencia[1].replace('jpeg', 'jpg') : 'webp';
  }

  async function subirImagen(archivo, carpeta) {
    if (!cliente) throw new Error('Supabase no está disponible.');
    validarArchivoImagen(archivo);

    const extension = extensionImagen(archivo);
    const nombre = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}.${extension}`;
    const ruta = `${carpeta}/${nombre}`;

    const { error } = await cliente.storage
      .from(BUCKET_IMAGENES)
      .upload(ruta, archivo, {
        cacheControl: '3600',
        upsert: false,
        contentType: archivo.type || undefined
      });

    if (error) throw new Error(error.message || 'No se pudo subir la imagen.');

    const { data } = cliente.storage.from(BUCKET_IMAGENES).getPublicUrl(ruta);
    if (!data || !data.publicUrl) throw new Error('No se pudo obtener la URL pública de la imagen.');
    return data.publicUrl;
  }

  async function subirImagenProducto(id, archivo) {
    const producto = buscarProducto(id);
    if (!producto) return;

    const card = buscarTarjetaProducto(id);
    const estado = card ? card.querySelector(`[data-upload-producto="${id}"]`) : null;

    try {
      validarArchivoImagen(archivo);
    } catch (error) {
      mostrarEstado(estado, error.message, 'error');
      return;
    }

    const token = (tokensUploadProducto.get(id) || 0) + 1;
    tokensUploadProducto.set(id, token);

    const preview = card ? card.querySelector(`[data-preview-producto="${id}"]`) : null;
    const previewAnterior = preview ? preview.src : '';
    const previewTemporal = crearPreviewTemporal(archivo);
    let subidaOk = false;

    if (previewTemporal) aplicarPreviewImagen(preview, previewTemporal);

    subidasPendientes += 1;
    actualizarBotonGuardar();
    mostrarEstado(estado, 'Subiendo imagen...', 'pendiente');

    try {
      const url = await subirImagen(archivo, 'productos');
      if (token !== tokensUploadProducto.get(id)) return;
      const actual = buscarProducto(id);
      if (!actual) return;
      actual.foto = url;
      subidaOk = true;
      marcarCambios();
      actualizarImagenProductoEnDom(id, url);
      mostrarEstado(estado, 'Imagen actualizada', 'ok');
    } catch (error) {
      if (token === tokensUploadProducto.get(id)) {
        if (preview && previewAnterior) aplicarPreviewImagen(preview, previewAnterior);
        mostrarEstado(estado, `Error: ${error.message}`, 'error');
      }
      mostrarAviso(esErrorPermiso(error) ? 'No tenés permiso para hacer esto.' : 'No se pudo subir la imagen. Verificá que el bucket carta-imagenes y sus permisos existan.', 'error');
    } finally {
      if (previewTemporal) {
        if (token === tokensUploadProducto.get(id) && subidaOk && preview && preview.src === previewTemporal) {
          aplicarPreviewImagen(preview, producto.foto || previewAnterior);
        }
        revocarPreviewTemporal(previewTemporal);
      }
      subidasPendientes = Math.max(0, subidasPendientes - 1);
      actualizarBotonGuardar();
    }
  }

  function actualizarImagenProductoEnDom(id, url) {
    const card = buscarTarjetaProducto(id);
    if (!card) return;
    const imagenes = card.querySelectorAll('.admin-prod-thumb, [data-preview-producto]');
    imagenes.forEach(imagen => {
      imagen.dataset.fallback = '';
      imagen.src = url;
    });
  }

  function abrirFormularioProducto() {
    const cat = categoriaPorId(categoriaActivaId);
    if (!cat) return;

    tokenUploadNuevo += 1;
    fotoNuevaProductoUrl = '';
    subiendoFotoNueva = false;
    el.formProducto.reset();
    if (el.productoCategoriaChip) el.productoCategoriaChip.textContent = cat.nombre || cat.id;
    if (el.productoTipoOferta) el.productoTipoOferta.value = 'dia';
    if (el.productoOfertaHasta) el.productoOfertaHasta.value = '';
    if (el.productoOfertaFechaCampo) el.productoOfertaFechaCampo.hidden = true;
    if (el.productoFotoFile) el.productoFotoFile.value = '';
    if (el.productoFotoPreview) {
      el.productoFotoPreview.dataset.fallback = '';
      el.productoFotoPreview.src = rutaImagenCategoria(cat);
    }
    mostrarEstado(el.productoFotoEstado, '');
    mostrarEstado(el.productoEstado, '');
    actualizarBotonAgregar();
    el.panelNuevoProducto.hidden = false;

    requestAnimationFrame(() => {
      if (typeof el.panelNuevoProducto.scrollIntoView === 'function') {
        el.panelNuevoProducto.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
      if (el.productoNombre) el.productoNombre.focus({ preventScroll: true });
    });
  }

  function cerrarFormularioProducto() {
    tokenUploadNuevo += 1;
    fotoNuevaProductoUrl = '';
    subiendoFotoNueva = false;
    if (el.panelNuevoProducto) el.panelNuevoProducto.hidden = true;
    if (el.formProducto) el.formProducto.reset();
    if (el.productoFotoFile) el.productoFotoFile.value = '';
    if (el.productoFotoPreview) {
      el.productoFotoPreview.dataset.fallback = '';
      el.productoFotoPreview.src = 'assets/logo.webp';
    }
    mostrarEstado(el.productoFotoEstado, '');
    mostrarEstado(el.productoEstado, '');
    actualizarBotonAgregar();
  }

  async function subirImagenNueva(archivo) {
    try {
      validarArchivoImagen(archivo);
    } catch (error) {
      mostrarEstado(el.productoFotoEstado, error.message, 'error');
      return;
    }

    const token = ++tokenUploadNuevo;
    const previewAnterior = el.productoFotoPreview ? el.productoFotoPreview.src : '';
    const previewTemporal = crearPreviewTemporal(archivo);
    let subidaOk = false;

    if (previewTemporal) aplicarPreviewImagen(el.productoFotoPreview, previewTemporal);

    subiendoFotoNueva = true;
    subidasPendientes += 1;
    actualizarBotonAgregar();
    actualizarBotonGuardar();
    mostrarEstado(el.productoFotoEstado, 'Subiendo imagen...', 'pendiente');

    try {
      const url = await subirImagen(archivo, 'productos');
      if (token !== tokenUploadNuevo) return;
      fotoNuevaProductoUrl = url;
      subidaOk = true;
      aplicarPreviewImagen(el.productoFotoPreview, url);
      mostrarEstado(el.productoFotoEstado, 'Imagen lista', 'ok');
    } catch (error) {
      if (token === tokenUploadNuevo) {
        if (previewAnterior) aplicarPreviewImagen(el.productoFotoPreview, previewAnterior);
        mostrarEstado(el.productoFotoEstado, `Error: ${error.message}`, 'error');
      }
      mostrarAviso(esErrorPermiso(error) ? 'No tenés permiso para hacer esto.' : 'No se pudo subir la imagen. Verificá que el bucket carta-imagenes y sus permisos existan.', 'error');
    } finally {
      if (previewTemporal) {
        if (token === tokenUploadNuevo && !subidaOk && previewAnterior) {
          aplicarPreviewImagen(el.productoFotoPreview, previewAnterior);
        }
        revocarPreviewTemporal(previewTemporal);
      }
      subidasPendientes = Math.max(0, subidasPendientes - 1);
      if (token === tokenUploadNuevo) {
        subiendoFotoNueva = false;
        actualizarBotonAgregar();
      }
      actualizarBotonGuardar();
    }
  }

  function agregarProducto(evento) {
    evento.preventDefault();
    const cat = categoriaPorId(categoriaActivaId);
    if (!cat) {
      mostrarEstado(el.productoEstado, 'Seleccioná una categoría antes de agregar un producto.', 'error');
      return;
    }

    if (subiendoFotoNueva) {
      mostrarEstado(el.productoEstado, 'Esperá a que termine de subir la imagen.', 'pendiente');
      return;
    }

    const nombre = el.productoNombre.value.trim();
    const descripcion = el.productoDescripcion.value.trim();
    const delivery = Number(el.productoDelivery.value);
    const mesa = Number(el.productoMesa.value);
    const tipoOfertaNueva = el.productoTipoOferta && TIPOS_OFERTA.includes(el.productoTipoOferta.value)
      ? el.productoTipoOferta.value
      : 'dia';
    const ofertaDeliveryTexto = el.productoDeliveryOferta ? el.productoDeliveryOferta.value.trim() : '';
    const ofertaMesaTexto = el.productoMesaOferta ? el.productoMesaOferta.value.trim() : '';
    const ofertaHasta = tipoOfertaNueva === 'fecha' && el.productoOfertaHasta
      ? isoDesdeFechaInput(el.productoOfertaHasta.value)
      : '';

    if (!nombre) {
      mostrarEstado(el.productoEstado, 'Escribí un nombre para el producto.', 'error');
      return;
    }

    if (!Number.isFinite(delivery) || delivery <= 0 || !Number.isFinite(mesa) || mesa <= 0) {
      mostrarEstado(el.productoEstado, 'Los precios de delivery y mesa deben ser mayores a cero.', 'error');
      return;
    }

    const idsExistentes = new Set(
      carta.productos
        .map(producto => producto && producto.id)
        .filter(Boolean)
    );
    const idProducto = PM.generarIdProducto(cat.id, nombre, idsExistentes);
    const agotado = !!(
      (el.productoAgotado && el.productoAgotado.checked)
      || (el.productoAgotadoPermanente && el.productoAgotadoPermanente.checked)
    );
    const permanente = !!(el.productoAgotadoPermanente && el.productoAgotadoPermanente.checked);

    const producto = {
      id: idProducto,
      categoria: cat.id,
      nombre: nombre,
      foto: fotoNuevaProductoUrl || rutaImagenCategoria(cat),
      sucursales: SUCURSALES_POR_DEFECTO.slice(),
      precios: {
        delivery: delivery,
        mesa: mesa
      },
      agotado: agotado,
      agotado_fecha: agotado ? PM.hoyArgentina() : null,
      agotado_hasta_nuevo_aviso: agotado ? permanente : false
    };

    if (descripcion) producto.descripcion = descripcion;

    const hayPrecioOferta = ofertaDeliveryTexto !== '' || ofertaMesaTexto !== '';

    if (hayPrecioOferta) {
      const deliveryOferta = Number(ofertaDeliveryTexto);
      const mesaOferta = Number(ofertaMesaTexto);

      if (!Number.isFinite(deliveryOferta) || deliveryOferta <= 0 || !Number.isFinite(mesaOferta) || mesaOferta <= 0) {
        mostrarEstado(el.productoEstado, 'Completá ambos precios de oferta o dejá los dos vacíos.', 'error');
        return;
      }

      if (deliveryOferta >= delivery || mesaOferta >= mesa) {
        mostrarEstado(el.productoEstado, 'Los precios de oferta deben ser menores a los originales.', 'error');
        return;
      }

      if (tipoOfertaNueva === 'fecha' && !ofertaHasta) {
        mostrarEstado(el.productoEstado, 'Elegí la fecha en la que termina la oferta.', 'error');
        return;
      }

      producto.delivery_oferta = deliveryOferta;
      producto.mesa_oferta = mesaOferta;
      producto.tipoOferta = tipoOfertaNueva;
      if (tipoOfertaNueva === 'fecha') producto.oferta_hasta = ofertaHasta;
    }

    carta.productos.push(producto);
    productosExpandidos.add(producto.id);
    marcarCambios();
    cerrarFormularioProducto();
    renderizarCategorias();
    renderizarDetalleCategoria();
    mostrarEstado(el.estado, 'Producto agregado. Guardá para publicarlo.', 'pendiente');
  }

  function crearSlug(texto) {
    return (PM.slugify(texto).slice(0, 40) || 'producto');
  }

  function crearIdCategoriaUnico(nombre) {
    const base = (PM.slugify(nombre).slice(0, 32) || 'categoria');
    let id = base;
    let contador = 2;
    while (categoriaValida(id)) {
      id = `${base}_${contador}`;
      contador += 1;
    }
    return id;
  }

  function abrirModalCategoria(modo, id) {
    tokenUploadCategoria += 1;
    subiendoCategoria = false;
    modalCategoriaModo = modo;
    categoriaEditandoId = id || null;
    fotoCategoriaSeleccionada = '';
    el.formCategoria.reset();
    if (el.categoriaFotoFile) el.categoriaFotoFile.value = '';
    mostrarEstado(el.categoriaEstado, '');
    mostrarEstado(el.categoriaFotoEstado, '');
    actualizarBotonGuardarCategoria();

    if (modo === 'editar') {
      const cat = categoriaPorId(id);
      if (!cat) return;
      if (el.modalCategoriaTitulo) el.modalCategoriaTitulo.textContent = 'Editar categoría';
      el.categoriaNombre.value = cat.nombre || '';
      fotoCategoriaSeleccionada = rutaImagenCategoria(cat);
      if (el.categoriaFotoPreview) {
        el.categoriaFotoPreview.dataset.fallback = '';
        el.categoriaFotoPreview.src = fotoCategoriaSeleccionada;
      }
    } else {
      if (el.modalCategoriaTitulo) el.modalCategoriaTitulo.textContent = 'Nueva categoría';
      if (el.categoriaFotoPreview) {
        el.categoriaFotoPreview.dataset.fallback = '';
        el.categoriaFotoPreview.src = 'assets/logo.webp';
      }
    }

    el.modalCategoria.hidden = false;
    document.body.classList.add('admin-modal-abierto');

    requestAnimationFrame(() => {
      if (el.categoriaNombre) el.categoriaNombre.focus({ preventScroll: true });
    });
  }

  function cerrarModalCategoria() {
    tokenUploadCategoria += 1;
    subiendoCategoria = false;
    modalCategoriaModo = 'crear';
    categoriaEditandoId = null;
    fotoCategoriaSeleccionada = '';
    if (el.modalCategoria) el.modalCategoria.hidden = true;
    if (el.formCategoria) el.formCategoria.reset();
    if (el.categoriaFotoFile) el.categoriaFotoFile.value = '';
    if (el.categoriaFotoPreview) {
      el.categoriaFotoPreview.dataset.fallback = '';
      el.categoriaFotoPreview.src = 'assets/logo.webp';
    }
    mostrarEstado(el.categoriaEstado, '');
    mostrarEstado(el.categoriaFotoEstado, '');
    document.body.classList.remove('admin-modal-abierto');
    actualizarBotonGuardarCategoria();
  }

  async function subirImagenCategoria(archivo) {
    try {
      validarArchivoImagen(archivo);
    } catch (error) {
      mostrarEstado(el.categoriaFotoEstado, error.message, 'error');
      return;
    }

    const token = ++tokenUploadCategoria;
    const previewAnterior = el.categoriaFotoPreview ? el.categoriaFotoPreview.src : '';
    const previewTemporal = crearPreviewTemporal(archivo);
    let subidaOk = false;

    if (previewTemporal) aplicarPreviewImagen(el.categoriaFotoPreview, previewTemporal);

    subiendoCategoria = true;
    actualizarBotonGuardarCategoria();
    mostrarEstado(el.categoriaFotoEstado, 'Subiendo imagen...', 'pendiente');

    try {
      const url = await subirImagen(archivo, 'categorias');
      if (token !== tokenUploadCategoria) return;
      fotoCategoriaSeleccionada = url;
      subidaOk = true;
      aplicarPreviewImagen(el.categoriaFotoPreview, url);
      mostrarEstado(el.categoriaFotoEstado, 'Imagen lista', 'ok');
    } catch (error) {
      if (token === tokenUploadCategoria) {
        if (previewAnterior) aplicarPreviewImagen(el.categoriaFotoPreview, previewAnterior);
        mostrarEstado(el.categoriaFotoEstado, `Error: ${error.message}`, 'error');
      }
      mostrarAviso(esErrorPermiso(error) ? 'No tenés permiso para hacer esto.' : 'No se pudo subir la imagen. Verificá que el bucket carta-imagenes y sus permisos existan.', 'error');
    } finally {
      if (previewTemporal) {
        if (token === tokenUploadCategoria && !subidaOk && previewAnterior) {
          aplicarPreviewImagen(el.categoriaFotoPreview, previewAnterior);
        }
        revocarPreviewTemporal(previewTemporal);
      }
      if (token === tokenUploadCategoria) {
        subiendoCategoria = false;
        actualizarBotonGuardarCategoria();
      }
    }
  }

  function guardarCategoria(evento) {
    evento.preventDefault();
    if (subiendoCategoria) {
      mostrarEstado(el.categoriaEstado, 'Esperá a que termine de subir la imagen.', 'pendiente');
      return;
    }

    const nombre = el.categoriaNombre.value.trim();
    if (!nombre) {
      mostrarEstado(el.categoriaEstado, 'Escribí un nombre para la categoría.', 'error');
      return;
    }

    if (modalCategoriaModo === 'editar') {
      const cat = categoriaPorId(categoriaEditandoId);
      if (!cat) {
        mostrarEstado(el.categoriaEstado, 'La categoría ya no existe.', 'error');
        return;
      }
      cat.nombre = nombre;
      cat.foto = fotoCategoriaSeleccionada || rutaImagenCategoria(cat);
      cerrarModalCategoria();
      marcarCambios();
      renderizarTodo();
      mostrarEstado(el.estado, 'Categoría actualizada. Guardá para publicar.', 'pendiente');
      return;
    }

    const id = crearIdCategoriaUnico(nombre);
    const nueva = {
      id: id,
      nombre: nombre,
      foto: fotoCategoriaSeleccionada || 'assets/logo.webp'
    };

    carta.categorias.push(nueva);
    cerrarModalCategoria();
    marcarCambios();
    seleccionarCategoria(id, true);
    mostrarEstado(el.estado, 'Categoría creada. Agregá sus productos y guardá.', 'pendiente');
  }

  function validarCarta() {
    if (!carta) return 'La carta no está cargada.';
    if (!Array.isArray(carta.categorias) || !carta.categorias.length) return 'La carta necesita al menos una categoría.';

    const categorias = new Set();
    for (const cat of carta.categorias) {
      if (!cat || !String(cat.id || '').trim()) return 'Hay una categoría sin ID interno.';
      if (!PM.validarId(cat.id)) return `La categoría "${cat.nombre || cat.id}" tiene un ID inválido. Usá minúsculas, números y guiones bajos.`;
      if (categorias.has(cat.id)) return `La categoría "${cat.id}" está duplicada.`;
      categorias.add(cat.id);
    }

    const ids = new Set();
    for (const producto of carta.productos) {
      if (!producto) return 'Hay un producto inválido en la carta.';
      const id = String(producto.id || '').trim();
      const nombre = String(producto.nombre || '').trim();
      if (!id) return 'Hay un producto sin ID interno.';
      if (!PM.validarId(id)) return `El producto "${nombre || id}" tiene un ID inválido. Usá minúsculas, números y guiones bajos.`;
      if (ids.has(id)) return `El ID "${id}" está duplicado.`;
      ids.add(id);
      if (!nombre) return 'Todos los productos necesitan un nombre.';
      if (!categorias.has(producto.categoria)) return `"${nombre}" tiene una categoría inválida.`;
      if (!id.startsWith(`${producto.categoria}_`)) return `El ID "${id}" debe empezar con "${producto.categoria}_".`;

      if (producto.tipoOferta && !TIPOS_OFERTA.includes(producto.tipoOferta)) {
        return `"${nombre}" tiene un tipo de oferta inválido.`;
      }

      const desde = producto.oferta_desde ? PM.parseFechaOferta(producto.oferta_desde) : null;
      const hasta = producto.oferta_hasta ? PM.parseFechaOferta(producto.oferta_hasta) : null;

      if (producto.oferta_desde && desde === null) {
        return `"${nombre}" tiene una fecha de inicio de oferta inválida.`;
      }
      if (producto.oferta_hasta && hasta === null) {
        return `"${nombre}" tiene una fecha de fin de oferta inválida.`;
      }
      if (desde !== null && hasta !== null && hasta <= desde) {
        return `En "${nombre}", el fin de la oferta debe ser posterior al inicio.`;
      }
      if (precioOfertaValido(producto) && tipoOfertaProducto(producto) === 'fecha' && hasta === null) {
        return `"${nombre}" tiene una oferta "Hasta una fecha" sin fecha de fin.`;
      }
    }

    return '';
  }

  function normalizarCartaParaGuardar() {
    if (!carta) return;

    carta.categorias.forEach(cat => {
      if (!cat) return;
      cat.nombre = String(cat.nombre || cat.id || '').trim() || cat.id;
      cat.foto = String(cat.foto || '').trim();
      if (!esRutaImagenSegura(cat.foto)) cat.foto = 'assets/logo.webp';
      if (!cat.foto) cat.foto = 'assets/logo.webp';
    });

    carta.productos.forEach(producto => {
      if (!producto) return;

      producto.nombre = String(producto.nombre || '').trim() || producto.id;
      producto.descripcion = String(producto.descripcion || '').trim();
      if (!producto.descripcion) delete producto.descripcion;

      if (!producto.precios || typeof producto.precios !== 'object') producto.precios = {};
      ['delivery', 'mesa'].forEach(campo => {
        const numero = Number(producto.precios[campo]);
        producto.precios[campo] = Number.isFinite(numero) && numero >= 0 ? numero : 0;
      });

      if (producto.tipoOferta !== undefined) {
        producto.tipoOferta = TIPOS_OFERTA.includes(producto.tipoOferta) ? producto.tipoOferta : 'dia';
      }

      const tienePrecioOferta = producto.delivery_oferta !== undefined || producto.mesa_oferta !== undefined;

      if (tienePrecioOferta) {
        const deliveryOferta = Number(producto.delivery_oferta);
        const mesaOferta = Number(producto.mesa_oferta);
        const delivery = producto.precios.delivery;
        const mesa = producto.precios.mesa;
        if (Number.isFinite(deliveryOferta) && deliveryOferta > 0 && deliveryOferta < delivery &&
            Number.isFinite(mesaOferta) && mesaOferta > 0 && mesaOferta < mesa) {
          producto.delivery_oferta = deliveryOferta;
          producto.mesa_oferta = mesaOferta;
          producto.tipoOferta = tipoOfertaProducto(producto);
        } else {
          delete producto.delivery_oferta;
          delete producto.mesa_oferta;
        }
      }

      if (!precioOfertaValido(producto)) {
        delete producto.tipoOferta;
        delete producto.oferta_desde;
        delete producto.oferta_hasta;
      } else if (tipoOfertaProducto(producto) === 'fecha') {
        delete producto.oferta_desde;
        const valorInput = PM.fechaOfertaParaInput(producto.oferta_hasta);
        const iso = valorInput ? PM.inputOfertaAIso(valorInput) : '';
        if (iso) producto.oferta_hasta = iso;
        else delete producto.oferta_hasta;
      } else {
        delete producto.oferta_desde;
        delete producto.oferta_hasta;
      }

      producto.foto = String(producto.foto || '').trim();
      if (!esRutaImagenSegura(producto.foto)) producto.foto = rutaImagenCategoria(categoriaPorId(producto.categoria));

      if (!Array.isArray(producto.sucursales) || producto.sucursales.length === 0) {
        producto.sucursales = SUCURSALES_POR_DEFECTO.slice();
      }

      PM.normalizarAgotado(producto);
      if (typeof producto.agotado !== 'boolean') producto.agotado = false;
      if (producto.agotado_fecha === undefined) producto.agotado_fecha = null;
      if (typeof producto.agotado_hasta_nuevo_aviso !== 'boolean') {
        producto.agotado_hasta_nuevo_aviso = false;
      }
    });
  }

  async function guardarCarta() {
    if (!cliente) {
      mostrarEstado(el.estado, 'Supabase no está disponible.', 'error');
      return;
    }
    if (!carta || guardando) return;

    if (subidasPendientes > 0) {
      mostrarEstado(el.estado, 'Esperá a que terminen de subir las imágenes.', 'pendiente');
      return;
    }

    const errorValidacion = validarCarta();
    if (errorValidacion) {
      mostrarEstado(el.estado, errorValidacion, 'error');
      mostrarAviso('Corregí los datos marcados antes de publicar.', 'error');
      return;
    }

    if (publicacionLocalRiesgosa) {
      const confirmado = window.confirm(
        'No se pudo leer la carta desde Supabase. Si publicás ahora, podrías pisar cambios hechos en otro dispositivo. ¿Publicar igual la copia local?'
      );
      if (!confirmado) {
        mostrarEstado(el.estado, 'Publicación cancelada.', 'pendiente');
        return;
      }
    }

    normalizarCartaParaGuardar();
    guardando = true;
    actualizarBotonGuardar();
    mostrarEstado(el.estado, 'Guardando en la nube...');

    try {
      const { error } = await cliente
        .from(tablaCarta())
        .upsert({
          id: filaCarta(),
          contenido: carta
        }, { onConflict: 'id' });

      if (error) throw error;

      cambiosPendientes = false;
      publicacionLocalRiesgosa = false;
      renderizarTodo();
      mostrarEstado(el.estado, 'Guardado y publicado en tiempo real', 'ok');
      mostrarAviso('');
    } catch (error) {
      const mensaje = error && error.message ? error.message : 'Error desconocido';
      if (esErrorPermiso(error)) {
        mostrarEstado(el.estado, 'No tenés permiso para hacer esto.', 'error');
        mostrarAviso('No tenés permiso para hacer esto.', 'error');
      } else {
        mostrarEstado(el.estado, `No se pudo guardar: ${mensaje}`, 'error');
        mostrarAviso('Verificá que hayas ejecutado las migraciones 001 y 002, que el email esté en la tabla admins y que la sesión siga activa.', 'error');
      }
    } finally {
      guardando = false;
      actualizarBotonGuardar();
    }
  }

  function exportarCarta() {
    if (!carta) return;
    const blob = new Blob([JSON.stringify(carta, null, 2) + '\n'], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const enlace = document.createElement('a');
    enlace.href = url;
    enlace.download = 'cartas.json';
    document.body.appendChild(enlace);
    enlace.click();
    enlace.remove();
    URL.revokeObjectURL(url);
    mostrarEstado(el.estado, 'JSON exportado', 'ok');
  }

  async function iniciarSesion(evento) {
    evento.preventDefault();
    if (!cliente) {
      mostrarEstado(el.loginEstado, 'Supabase no está configurado o no se pudo cargar.', 'error');
      return;
    }

    const email = el.emailInput.value.trim();
    const password = el.passwordInput.value;

    if (!email || !password) {
      mostrarEstado(el.loginEstado, 'Completá el email y la contraseña.', 'error');
      return;
    }

    el.btnLogin.disabled = true;
    mostrarEstado(el.loginEstado, 'Ingresando...');

    try {
      // AQUÍ ESTÁ LA CORRECCIÓN: Autenticación real con Supabase Auth
      const { error } = await cliente.auth.signInWithPassword({ email, password });
      if (error) {
        mostrarEstado(el.loginEstado, 'No se pudo ingresar: ' + error.message, 'error');
        return;
      }
      mostrarEstado(el.loginEstado, '');
    } catch (error) {
      mostrarEstado(el.loginEstado, 'No se pudo ingresar: ' + (error.message || 'error de conexión'), 'error');
    } finally {
      el.btnLogin.disabled = false;
    }
  }

  async function cerrarSesion() {
    if (!cliente) return;
    try {
      await cliente.auth.signOut();
    } catch (error) {
      console.warn(error);
    }
    cambiosPendientes = false;
    pedidos = [];
    pedidosCargados = false;
    actualizarBadgePedidos();
    mostrarLogin();
  }

  function abrirSelectorArchivo(input) {
    if (!input) return;
    input.value = '';
    input.click();
  }

  function conectarZonaArchivo(zona, input) {
    if (!zona || !input) return;
    zona.addEventListener('click', (evento) => {
      if (evento.target.closest('button, input, a, label, select, textarea')) return;
      abrirSelectorArchivo(input);
    });
  }

  const ESTADOS_PEDIDO = {
    pendiente: 'Nuevo',
    confirmado: 'En preparación',
    listo: 'Listo para entregar',
    en_camino: 'En camino',
    entregado: 'Completado',
    cancelado: 'Cancelado'
  };

  const CLAVE_CANCELADOS_ABIERTO = 'pm_cancelados_abierto';

  function canceladosAbierto() {
    try { return sessionStorage.getItem(CLAVE_CANCELADOS_ABIERTO) === '1'; } catch (e) { return false; }
  }

  function guardarCanceladosAbierto(abierto) {
    try { sessionStorage.setItem(CLAVE_CANCELADOS_ABIERTO, abierto ? '1' : '0'); } catch (e) { /* sin storage */ }
  }

  function aplicarEstadoColumnaCancelados(columna, colapsada) {
    columna.classList.toggle('colapsada', colapsada);
    const boton = columna.querySelector('[data-columna-toggle]');
    if (!boton) return;
    boton.setAttribute('aria-expanded', colapsada ? 'false' : 'true');
    boton.setAttribute('aria-label', `${colapsada ? 'Expandir' : 'Cerrar'} columna Cancelados`);
    boton.textContent = colapsada ? '‹' : '✕';
  }

  const COLUMNAS_PEDIDO = [
    { clave: 'pendiente', titulo: 'Nuevos' },
    { clave: 'confirmado', titulo: 'En preparación' },
    { clave: 'listo', titulo: 'Listos para entregar' },
    { clave: 'en_camino', titulo: 'En camino', soloDelivery: true },
    { clave: 'entregado', titulo: 'Completados' },
    { clave: 'cancelado', titulo: 'Cancelados', colapsable: true }
  ];

  function iconoModalidadPedido(modalidad) {
    const valor = String(modalidad || '').toLowerCase();
    if (valor === 'delivery') {
      return '<svg class="admin-pedido-icono" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7h11v8H3zM14 10h4l3 3v2h-7zM7 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4Zm10 0a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>';
    }
    return '<svg class="admin-pedido-icono" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 8h12l-1 12H7L6 8Zm3 0V6a3 3 0 0 1 6 0v2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>';
  }

  function siguienteEstadoPedido(pedido) {
    if (!pedido) return '';
    if (pedido.estado === 'pendiente') return 'confirmado';
    if (pedido.estado === 'confirmado') return 'listo';
    if (pedido.estado === 'listo') return pedido.modalidad === 'delivery' ? 'en_camino' : 'entregado';
    if (pedido.estado === 'en_camino') return 'entregado';
    return '';
  }

  function etiquetaBotonAvance(pedido) {
    if (!pedido) return '';
    if (pedido.estado === 'pendiente') return 'Iniciar preparación';
    if (pedido.estado === 'confirmado') return 'Marcar listo';
    if (pedido.estado === 'listo') return pedido.modalidad === 'delivery' ? 'En camino' : 'Completar';
    if (pedido.estado === 'en_camino') return 'Completar';
    return '';
  }

  function pedidoEsEfectivo(pedido) {
    return String(pedido && pedido.metodo_pago || '').toLowerCase().includes('efectivo');
  }

  function mostrarBotonPagado(pedido) {
    if (!pedidosSoportaPagos || !pedido || pedido.pagado === true) return false;
    if (!pedidoEsEfectivo(pedido)) return true;
    return ['listo', 'en_camino', 'entregado'].includes(pedido.estado);
  }

  function mostrarEstadoPedidos(texto, tipo = '') {
    mostrarEstado(el.pedidosEstado, texto, tipo);
  }

  function mostrarAvisoPedidos(texto, tipo = 'info') {
    if (!el.pedidosAviso) return;
    if (!texto) {
      el.pedidosAviso.hidden = true;
      el.pedidosAviso.textContent = '';
      return;
    }
    el.pedidosAviso.hidden = false;
    el.pedidosAviso.dataset.tipo = tipo;
    el.pedidosAviso.textContent = texto;
  }

  function poblarFiltroSucursalesPedidos() {
    if (!el.pedidosFiltroSucursal) return;
    if (esAdminSucursal()) {
      el.pedidosFiltroSucursal.disabled = true;
      if (!adminSucursalId) {
        el.pedidosFiltroSucursal.innerHTML = '<option value="">Sin sucursal asignada</option>';
        el.pedidosFiltroSucursal.value = '';
        return;
      }
      const nombre = SUCURSALES_NOMBRES[adminSucursalId] || adminSucursalId;
      el.pedidosFiltroSucursal.innerHTML = `<option value="${escaparHtml(adminSucursalId)}">${escaparHtml(nombre)}</option>`;
      el.pedidosFiltroSucursal.value = adminSucursalId;
      return;
    }
    el.pedidosFiltroSucursal.disabled = false;
    const actual = el.pedidosFiltroSucursal.value;
    const opciones = Object.keys(SUCURSALES_NOMBRES)
      .sort((a, b) => SUCURSALES_NOMBRES[a].localeCompare(SUCURSALES_NOMBRES[b], 'es'))
      .map(id => `<option value="${PM.escaparHtml(id)}">${PM.escaparHtml(SUCURSALES_NOMBRES[id])}</option>`)
      .join('');
    el.pedidosFiltroSucursal.innerHTML = `<option value="">Todas</option>${opciones}`;
    if (actual) el.pedidosFiltroSucursal.value = actual;
  }

  function nombreSucursalPedido(id) {
    return SUCURSALES_NOMBRES[id] || id || '-';
  }

  function nombreEstadoPedido(estado) {
    return ESTADOS_PEDIDO[estado] || estado || 'Sin estado';
  }

  function etiquetaModalidadPedido(modalidad) {
    const valor = String(modalidad || '').toLowerCase();
    if (valor === 'delivery') return 'Delivery';
    if (valor === 'retiro') return 'Para llevar';
    return modalidad || '-';
  }

  function telefonoSoloDigitos(valor) {
    return String(valor || '').replace(/\D/g, '');
  }

  function fechaHoraPedido(iso) {
    const fecha = new Date(iso);
    if (!Number.isFinite(fecha.getTime())) return '';
    try {
      return fecha.toLocaleString('es-AR', {
        timeZone: 'America/Argentina/Buenos_Aires',
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch (error) {
      return fecha.toLocaleString('es-AR');
    }
  }

  function horaPedido(iso) {
    const fecha = new Date(iso);
    if (!Number.isFinite(fecha.getTime())) return '';
    try {
      return fecha.toLocaleTimeString('es-AR', {
        timeZone: 'America/Argentina/Buenos_Aires',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch (error) {
      return '';
    }
  }

  function fechaArgentinaHoy() {
    try {
      return new Date().toLocaleDateString('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' });
    } catch (error) {
      return new Date().toISOString().slice(0, 10);
    }
  }

  function fechaPedidoArgentina(iso) {
    const fecha = new Date(iso);
    if (!Number.isFinite(fecha.getTime())) return '';
    try {
      return fecha.toLocaleDateString('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' });
    } catch (error) {
      return fecha.toISOString().slice(0, 10);
    }
  }

  function fechaUTCDesdeISO(fechaISO) {
    const partes = String(fechaISO || '').split('-').map(Number);
    if (partes.length !== 3 || !partes.every(Number.isFinite)) return null;
    const fecha = new Date(Date.UTC(partes[0], partes[1] - 1, partes[2], 12));
    if (!Number.isFinite(fecha.getTime())) return null;
    return fecha;
  }

  function sumarDiasFecha(fechaISO, dias) {
    const fecha = fechaUTCDesdeISO(fechaISO) || fechaUTCDesdeISO(fechaArgentinaHoy());
    fecha.setUTCDate(fecha.getUTCDate() + dias);
    return fecha.toISOString().slice(0, 10);
  }

  function sumarMesesFecha(fechaISO, meses) {
    const fecha = fechaUTCDesdeISO(fechaISO) || fechaUTCDesdeISO(fechaArgentinaHoy());
    fecha.setUTCDate(1);
    fecha.setUTCMonth(fecha.getUTCMonth() + meses, 1);
    return fecha.toISOString().slice(0, 10);
  }

  function inicioSemanaFecha(fechaISO) {
    const fecha = fechaUTCDesdeISO(fechaISO) || fechaUTCDesdeISO(fechaArgentinaHoy());
    const dia = fecha.getUTCDay();
    const desplazamiento = (dia + 6) % 7;
    return sumarDiasFecha(fecha.toISOString().slice(0, 10), -desplazamiento);
  }

  function inicioMesFecha(fechaISO) {
    const fecha = fechaUTCDesdeISO(fechaISO) || fechaUTCDesdeISO(fechaArgentinaHoy());
    return new Date(Date.UTC(fecha.getUTCFullYear(), fecha.getUTCMonth(), 1, 12)).toISOString().slice(0, 10);
  }

  function finMesFecha(fechaISO) {
    const fecha = fechaUTCDesdeISO(fechaISO) || fechaUTCDesdeISO(fechaArgentinaHoy());
    return new Date(Date.UTC(fecha.getUTCFullYear(), fecha.getUTCMonth() + 1, 0, 12)).toISOString().slice(0, 10);
  }

  function formatearFechaDiaPedidos(fechaISO) {
    const fecha = fechaUTCDesdeISO(fechaISO);
    if (!fecha) return '';
    try {
      const texto = new Intl.DateTimeFormat('es-AR', {
        weekday: 'long',
        day: 'numeric',
        month: 'long',
        timeZone: 'UTC'
      }).format(fecha).replace(',', '');
      return texto.charAt(0).toUpperCase() + texto.slice(1);
    } catch (error) {
      return fechaISO;
    }
  }

  function formatearFechaCortaPedidos(fechaISO) {
    const fecha = fechaUTCDesdeISO(fechaISO);
    if (!fecha) return '';
    try {
      return new Intl.DateTimeFormat('es-AR', {
        day: 'numeric',
        month: 'short',
        timeZone: 'UTC'
      }).format(fecha).replace(/\./g, '');
    } catch (error) {
      return fechaISO;
    }
  }

  function formatearMesPedidos(fechaISO) {
    const fecha = fechaUTCDesdeISO(fechaISO);
    if (!fecha) return '';
    try {
      const texto = new Intl.DateTimeFormat('es-AR', {
        month: 'long',
        year: 'numeric',
        timeZone: 'UTC'
      }).format(fecha).replace(/\s+de\s+/i, ' ');
      return texto.charAt(0).toUpperCase() + texto.slice(1);
    } catch (error) {
      return fechaISO.slice(0, 7);
    }
  }

  function rangoPedidosActual() {
    const hoy = fechaArgentinaHoy();
    const referencia = pedidosFechaDia || hoy;
    if (pedidosPeriodo === 'semana') {
      const desde = inicioSemanaFecha(referencia);
      return { desde, hasta: sumarDiasFecha(desde, 6) };
    }
    if (pedidosPeriodo === 'mes') {
      return { desde: inicioMesFecha(referencia), hasta: finMesFecha(referencia) };
    }
    if (pedidosPeriodo === 'personalizado') {
      let desde = (el.pedidosFiltroDesde && el.pedidosFiltroDesde.value) || hoy;
      let hasta = (el.pedidosFiltroHasta && el.pedidosFiltroHasta.value) || desde;
      if (desde > hasta) [desde, hasta] = [hasta, desde];
      return { desde, hasta };
    }
    return { desde: referencia, hasta: referencia };
  }

  function etiquetaPeriodoPedidos(rango) {
    const hoy = fechaArgentinaHoy();
    if (pedidosPeriodo === 'dia') {
      if (rango.desde === hoy) return 'Hoy';
      if (rango.desde === sumarDiasFecha(hoy, -1)) return 'Ayer';
      return formatearFechaDiaPedidos(rango.desde);
    }
    if (pedidosPeriodo === 'semana') {
      if (rango.desde === inicioSemanaFecha(hoy)) return 'Esta semana';
      return `${formatearFechaCortaPedidos(rango.desde)} – ${formatearFechaCortaPedidos(rango.hasta)}`;
    }
    if (pedidosPeriodo === 'mes') {
      return formatearMesPedidos(rango.desde);
    }
    if (rango.desde === rango.hasta) return formatearFechaDiaPedidos(rango.desde);
    return `${formatearFechaCortaPedidos(rango.desde)} – ${formatearFechaCortaPedidos(rango.hasta)}`;
  }

  function rangoPeriodoSiguiente() {
    const rango = rangoPedidosActual();
    if (pedidosPeriodo === 'semana') {
      const desde = sumarDiasFecha(rango.desde, 7);
      return { desde, hasta: sumarDiasFecha(desde, 6) };
    }
    if (pedidosPeriodo === 'mes') {
      const desde = sumarMesesFecha(inicioMesFecha(rango.desde), 1);
      return { desde, hasta: finMesFecha(desde) };
    }
    if (pedidosPeriodo === 'personalizado') {
      return { desde: sumarDiasFecha(rango.desde, 1), hasta: sumarDiasFecha(rango.hasta, 1) };
    }
    const fecha = sumarDiasFecha(rango.desde, 1);
    return { desde: fecha, hasta: fecha };
  }

  function puedeAvanzarPeriodoPedidos() {
    const siguiente = rangoPeriodoSiguiente();
    const hoy = fechaArgentinaHoy();
    if (pedidosPeriodo === 'personalizado') return siguiente.hasta <= hoy;
    return siguiente.desde <= hoy;
  }

  function pedidoCoincideFiltros(pedido) {
    if (!pedidoCuentaComoVenta(pedido)) return false;
    const sucursal = (el.pedidosFiltroSucursal && el.pedidosFiltroSucursal.value) || '';
    if (sucursal && pedido.sucursal_id !== sucursal) return false;
    if (pedidosModalidad && pedido.modalidad !== pedidosModalidad) return false;
    const fecha = fechaPedidoArgentina(pedido.created_at);
    if (!fecha) return false;
    const rango = rangoPedidosActual();
    return fecha >= rango.desde && fecha <= rango.hasta;
  }

  function pedidosFiltrados() {
    return pedidos.filter(pedidoCoincideFiltros);
  }

  function inicializarFiltrosPedidos() {
    pedidosFechaDia = fechaArgentinaHoy();
    pedidosPeriodo = 'dia';
    if (el.pedidosFiltroDesde) el.pedidosFiltroDesde.value = pedidosFechaDia;
    if (el.pedidosFiltroHasta) el.pedidosFiltroHasta.value = pedidosFechaDia;
    actualizarControlesPedidos();
  }

  function actualizarControlesPedidos() {
    const esPersonalizado = pedidosPeriodo === 'personalizado';
    const rango = rangoPedidosActual();
    const hoy = fechaArgentinaHoy();

    if (el.pedidosFiltroPeriodo && el.pedidosFiltroPeriodo.value !== pedidosPeriodo) {
      el.pedidosFiltroPeriodo.value = pedidosPeriodo;
    }
    if (el.pedidosRango) el.pedidosRango.hidden = !esPersonalizado;
    if (el.pedidosPeriodoEtiqueta) el.pedidosPeriodoEtiqueta.textContent = etiquetaPeriodoPedidos(rango);
    if (el.pedidosFiltroDesde) {
      el.pedidosFiltroDesde.max = hoy;
      if (esPersonalizado && el.pedidosFiltroDesde.value !== rango.desde) el.pedidosFiltroDesde.value = rango.desde;
    }
    if (el.pedidosFiltroHasta) {
      el.pedidosFiltroHasta.max = hoy;
      if (esPersonalizado && el.pedidosFiltroHasta.value !== rango.hasta) el.pedidosFiltroHasta.value = rango.hasta;
    }
    if (el.btnPedidosSiguiente) {
      const puedeAvanzar = puedeAvanzarPeriodoPedidos();
      el.btnPedidosSiguiente.disabled = !puedeAvanzar;
      el.btnPedidosSiguiente.setAttribute('aria-disabled', puedeAvanzar ? 'false' : 'true');
    }
    el.pedidosVistaBtns.forEach(boton => {
      const activo = boton.dataset.pedidosVista === pedidosVista;
      boton.classList.toggle('activa', activo);
      boton.setAttribute('aria-pressed', activo ? 'true' : 'false');
    });
    el.pedidosModalidadBtns.forEach(boton => {
      const activo = (boton.dataset.pedidosModalidad || '') === pedidosModalidad;
      boton.classList.toggle('activa', activo);
      boton.setAttribute('aria-pressed', activo ? 'true' : 'false');
    });
  }

  function moverPeriodoPedidos(direccion) {
    if (direccion > 0 && !puedeAvanzarPeriodoPedidos()) return;
    const rango = rangoPedidosActual();
    if (pedidosPeriodo === 'personalizado') {
      if (el.pedidosFiltroDesde) el.pedidosFiltroDesde.value = sumarDiasFecha(rango.desde, direccion);
      if (el.pedidosFiltroHasta) el.pedidosFiltroHasta.value = sumarDiasFecha(rango.hasta, direccion);
      pedidosFechaDia = sumarDiasFecha(rango.desde, direccion);
    } else if (pedidosPeriodo === 'semana') {
      pedidosFechaDia = sumarDiasFecha(rango.desde, direccion * 7);
    } else if (pedidosPeriodo === 'mes') {
      pedidosFechaDia = sumarMesesFecha(inicioMesFecha(rango.desde), direccion);
    } else {
      pedidosFechaDia = sumarDiasFecha(rango.desde, direccion);
    }
    actualizarControlesPedidos();
    renderPedidos();
  }

  function cambiarPeriodoPedidos(valor) {
    const permitidos = ['dia', 'semana', 'mes', 'personalizado'];
    const nuevo = permitidos.includes(valor) ? valor : 'dia';
    const rangoAnterior = rangoPedidosActual();
    if (nuevo === 'personalizado') {
      if (el.pedidosFiltroDesde) el.pedidosFiltroDesde.value = rangoAnterior.desde;
      if (el.pedidosFiltroHasta) el.pedidosFiltroHasta.value = rangoAnterior.hasta;
      pedidosFechaDia = rangoAnterior.desde;
    } else if (nuevo === 'mes') {
      pedidosFechaDia = inicioMesFecha(rangoAnterior.desde);
    } else {
      pedidosFechaDia = rangoAnterior.desde;
    }
    pedidosPeriodo = nuevo;
    actualizarControlesPedidos();
    renderPedidos();
  }

  function volverAHoyPedidos() {
    pedidosPeriodo = 'dia';
    pedidosFechaDia = fechaArgentinaHoy();
    if (el.pedidosFiltroDesde) el.pedidosFiltroDesde.value = pedidosFechaDia;
    if (el.pedidosFiltroHasta) el.pedidosFiltroHasta.value = pedidosFechaDia;
    actualizarControlesPedidos();
    renderPedidos();
  }

  function aplicarCambioRangoPedidos(origen) {
    const hoy = fechaArgentinaHoy();
    let desde = (el.pedidosFiltroDesde && el.pedidosFiltroDesde.value) || hoy;
    let hasta = (el.pedidosFiltroHasta && el.pedidosFiltroHasta.value) || desde;
    if (desde > hoy) desde = hoy;
    if (hasta > hoy) hasta = hoy;
    if (desde > hasta) {
      if (origen === 'desde') hasta = desde;
      else desde = hasta;
    }
    if (el.pedidosFiltroDesde) el.pedidosFiltroDesde.value = desde;
    if (el.pedidosFiltroHasta) el.pedidosFiltroHasta.value = hasta;
    pedidosFechaDia = desde;
    actualizarControlesPedidos();
    renderPedidos();
  }

  function pedidoCuentaComoVenta(pedido) {
    return !!pedido && pedido.sincronizado !== false;
  }

  function contarPedidosNuevos() {
    return pedidos.filter(pedido =>
      pedidoCuentaComoVenta(pedido)
      && pedido.estado === 'pendiente'
      && pedidoVisiblePorRol(pedido)
    ).length;
  }

  function actualizarBadgePedidos() {
    if (!el.pedidosBadge) return;
    const pendientes = contarPedidosNuevos();
    el.pedidosBadge.textContent = String(pendientes);
    el.pedidosBadge.hidden = pendientes === 0;
  }

  function columnaPedido(pedido) {
    if (!pedido) return '';
    if (pedido.estado === 'en_camino' && pedido.modalidad !== 'delivery') return 'listo';
    return COLUMNAS_PEDIDO.some(columna => columna.clave === pedido.estado) ? pedido.estado : '';
  }

  function resumenItemsPedido(pedido) {
    const items = Array.isArray(pedido && pedido.items_snapshot) ? pedido.items_snapshot : [];
    if (!items.length) return '';
    const filas = items.map(item => {
      const cantidad = Number(item && item.cantidad) || 0;
      const nombre = PM.escaparHtml(item && item.nombre ? item.nombre : 'Producto');
      return `<li><strong>${cantidad}×</strong> ${nombre}</li>`;
    }).join('');
    return `<details class="admin-pedido-resumen">
      <summary>Ítems (${items.length})</summary>
      <ul>${filas}</ul>
    </details>`;
  }

  function botonesPedido(pedido) {
    const botones = [];
    const avance = siguienteEstadoPedido(pedido);
    if (avance) {
      botones.push(`<button type="button" class="btn-primario" data-pedido-accion="avanzar">${PM.escaparHtml(etiquetaBotonAvance(pedido))}</button>`);
    }
    botones.push('<button type="button" class="btn-secundario" data-pedido-accion="imprimir">Imprimir</button>');
    if (mostrarBotonPagado(pedido)) {
      botones.push('<button type="button" class="btn-secundario" data-pedido-accion="pagado">Marcar pagado</button>');
    }
    if (pedido.estado !== 'cancelado' && pedido.estado !== 'entregado') {
      botones.push('<button type="button" class="btn-peligro" data-pedido-accion="cancelado">Cancelar</button>');
    }
    return botones.join('');
  }

  function crearTarjetaPedidoHtml(pedido) {
    const estado = ESTADOS_PEDIDO[pedido.estado] ? pedido.estado : 'desconocido';
    const id = PM.escaparHtml(pedido.id);
    const numero = PM.escaparHtml(pedido.numero_orden || 'Sin número');
    const cliente = PM.escaparHtml(pedido.cliente_nombre || 'Sin nombre');
    const sucursal = PM.escaparHtml(nombreSucursalPedido(pedido.sucursal_id));
    const modalidad = PM.escaparHtml(etiquetaModalidadPedido(pedido.modalidad));
    const pago = PM.escaparHtml(pedido.metodo_pago || '-');
    const hora = PM.escaparHtml(horaPedido(pedido.created_at));
    const pagado = pedido.pagado === true;
    const pagoClase = pagado ? 'pagado' : 'pendiente';

    return `<article class="admin-pedido-tarjeta estado-${estado}" data-pedido-id="${id}" data-estado="${estado}" data-created-at="${PM.escaparHtml(pedido.created_at || '')}">
      <div class="admin-pedido-tarjeta-top">
        <strong class="admin-pedido-numero">${numero}</strong>
        <span class="admin-pedido-hora">${hora}</span>
      </div>
      <div class="admin-pedido-tarjeta-cliente">
        <span class="admin-pedido-cliente">${cliente}</span>
        <span class="admin-pedido-modalidad">${iconoModalidadPedido(pedido.modalidad)}${modalidad}</span>
      </div>
      <div class="admin-pedido-tarjeta-meta">
        <span>${sucursal}</span>
        <span>${pago}</span>
        <span class="admin-pedido-pago ${pagoClase}">${pagado ? 'Pagado' : 'Pago pendiente'}</span>
        <strong>${formatearPrecio(pedido.total)}</strong>
      </div>
      ${resumenItemsPedido(pedido)}
      <div class="admin-pedido-tarjeta-acciones">${botonesPedido(pedido)}</div>
    </article>`;
  }

  function crearTarjetaPedido(pedido) {
    const contenedor = document.createElement('div');
    contenedor.innerHTML = crearTarjetaPedidoHtml(pedido);
    return contenedor.firstElementChild;
  }

  function insertarTarjetaOrdenada(contenedor, tarjeta) {
    if (!contenedor || !tarjeta) return;
    const fecha = tarjeta.dataset.createdAt || '';
    const existentes = Array.from(contenedor.querySelectorAll('[data-pedido-id]'));
    const referencia = existentes.find(item => (item.dataset.createdAt || '') < fecha);
    if (referencia) contenedor.insertBefore(tarjeta, referencia);
    else contenedor.appendChild(tarjeta);
  }

  function buscarTarjetaPedido(contenedor, id) {
    if (!contenedor) return null;
    return Array.from(contenedor.querySelectorAll('[data-pedido-id]'))
      .find(tarjeta => tarjeta.dataset.pedidoId === String(id)) || null;
  }

  function renderPedidos() {
    if (!el.pedidosTablero || !el.pedidosLista) return;
    const esLista = pedidosVista === 'lista';
    el.pedidosTablero.hidden = esLista;
    el.pedidosLista.hidden = !esLista;
    if (esLista) renderPedidosLista();
    else renderPedidosTablero();
  }

  function renderPedidosTablero() {
    if (!el.pedidosTablero) return;
    const lista = pedidosFiltrados();
    const cuerpoPrevio = el.pedidosTablero.querySelector('[data-columna="cancelado"] .admin-pedidos-columna-cuerpo');
    const scrollCancelados = cuerpoPrevio ? cuerpoPrevio.scrollTop : 0;
    const scrollTablero = el.pedidosTablero.scrollLeft;
    el.pedidosTablero.innerHTML = COLUMNAS_PEDIDO.map(columna => {
      const pedidosColumna = lista.filter(pedido => columnaPedido(pedido) === columna.clave
        && (!columna.soloDelivery || pedido.modalidad === 'delivery'));
      const tarjetas = pedidosColumna.map(crearTarjetaPedidoHtml).join('');
      const vacio = pedidosColumna.length ? '' : '<p class="admin-pedidos-vacio-columna">Sin pedidos.</p>';
      const colapsada = !!columna.colapsable && !canceladosAbierto();
      return `<section class="admin-pedidos-columna columna-${columna.clave} ${colapsada ? 'colapsada' : ''}" data-columna="${columna.clave}">
        <header class="admin-pedidos-columna-head">
          <div class="admin-pedidos-columna-titulo">
            <h3>${PM.escaparHtml(columna.titulo)}</h3>
            <span class="admin-pedidos-contador" data-contador="${columna.clave}">${pedidosColumna.length}</span>
          </div>
          ${columna.colapsable ? `<button type="button" class="btn-icono admin-pedidos-colapsar" data-columna-toggle aria-expanded="${colapsada ? 'false' : 'true'}" aria-label="${colapsada ? 'Expandir' : 'Cerrar'} columna Cancelados">${colapsada ? '‹' : '✕'}</button>` : ''}
        </header>
        <div class="admin-pedidos-columna-cuerpo">${tarjetas}${vacio}</div>
      </section>`;
    }).join('');
    el.pedidosTablero.scrollLeft = scrollTablero;
    const cuerpoNuevo = el.pedidosTablero.querySelector('[data-columna="cancelado"] .admin-pedidos-columna-cuerpo');
    if (cuerpoNuevo) cuerpoNuevo.scrollTop = scrollCancelados;
  }

  function renderPedidosLista() {
    if (!el.pedidosLista) return;
    const lista = pedidosFiltrados();
    if (!lista.length) {
      el.pedidosLista.innerHTML = '<p class="admin-vacio">No hay pedidos para estos filtros.</p>';
      return;
    }
    el.pedidosLista.innerHTML = lista.map(crearTarjetaPedidoHtml).join('');
  }

  function actualizarContadoresColumnas() {
    if (!el.pedidosTablero) return;
    COLUMNAS_PEDIDO.forEach(columna => {
      const contenedor = el.pedidosTablero.querySelector(`[data-columna="${columna.clave}"] .admin-pedidos-columna-cuerpo`);
      if (!contenedor) return;
      const tarjetas = contenedor.querySelectorAll('[data-pedido-id]');
      const contador = el.pedidosTablero.querySelector(`[data-contador="${columna.clave}"]`);
      if (contador) contador.textContent = String(tarjetas.length);
      const vacio = contenedor.querySelector('.admin-pedidos-vacio-columna');
      if (tarjetas.length && vacio) vacio.remove();
      if (!tarjetas.length && !vacio) {
        const parrafo = document.createElement('p');
        parrafo.className = 'admin-pedidos-vacio-columna';
        parrafo.textContent = 'Sin pedidos.';
        contenedor.appendChild(parrafo);
      }
    });
  }

  function actualizarTarjetaEnVista(pedido) {
    if (!pedidosCargados || !pedido) return;
    if (pedidosVista === 'tablero') {
      if (!el.pedidosTablero) return;
      const existente = buscarTarjetaPedido(el.pedidosTablero, pedido.id);
      if (!pedidoCoincideFiltros(pedido)) {
        if (existente) existente.remove();
        actualizarContadoresColumnas();
        return;
      }
      const columna = columnaPedido(pedido);
      const destino = columna
        ? el.pedidosTablero.querySelector(`[data-columna="${columna}"] .admin-pedidos-columna-cuerpo`)
        : null;
      if (!destino) {
        renderPedidosTablero();
        return;
      }
      const nueva = crearTarjetaPedido(pedido);
      if (existente) existente.remove();
      insertarTarjetaOrdenada(destino, nueva);
      actualizarContadoresColumnas();
      return;
    }

    if (!el.pedidosLista) return;
    const existente = buscarTarjetaPedido(el.pedidosLista, pedido.id);
    if (!pedidoCoincideFiltros(pedido)) {
      if (existente) existente.remove();
    } else {
      const nueva = crearTarjetaPedido(pedido);
      if (existente) existente.replaceWith(nueva);
      else insertarTarjetaOrdenada(el.pedidosLista, nueva);
    }
    const vacio = el.pedidosLista.querySelector('.admin-vacio');
    const hayTarjetas = !!el.pedidosLista.querySelector('[data-pedido-id]');
    if (!hayTarjetas && !vacio) {
      el.pedidosLista.innerHTML = '<p class="admin-vacio">No hay pedidos para estos filtros.</p>';
    } else if (hayTarjetas && vacio) {
      vacio.remove();
    }
  }

  function renderPedidoDetalle(pedido) {
    if (!el.pedidoDetalleContenido) return;

    if (!pedido) {
      el.pedidoDetalleContenido.innerHTML = '';
      return;
    }

    const telefono = telefonoSoloDigitos(pedido.cliente_telefono);
    const items = Array.isArray(pedido.items_snapshot) ? pedido.items_snapshot : [];
    const itemsHtml = items.map(item => {
      const cantidad = Number(item && item.cantidad) || 0;
      const nombre = PM.escaparHtml(item && item.nombre ? item.nombre : 'Producto');
      const especificaciones = [];
      if (item && item.variacion && item.variacion.nombre) {
        especificaciones.push(PM.escaparHtml(item.variacion.nombre));
      }
      if (item && Array.isArray(item.adicionales)) {
        item.adicionales.forEach(adicional => {
          if (adicional && adicional.nombre) especificaciones.push(PM.escaparHtml(adicional.nombre));
        });
      }
      const extrasHtml = especificaciones.length
        ? `<div class="admin-pedido-item-extras">${especificaciones.join(' · ')}</div>`
        : '';
      return `<div class="admin-pedido-item">
        <div class="admin-pedido-item-info">
          <span class="admin-pedido-item-nombre">${cantidad} × ${nombre}</span>
          ${extrasHtml}
          <small>${formatearPrecio(item && item.precio_unitario)} c/u</small>
        </div>
        <strong>${formatearPrecio(item && item.subtotal)}</strong>
      </div>`;
    }).join('');

    const tieneCoordenadas = Number.isFinite(Number(pedido.lat)) && Number.isFinite(Number(pedido.lng));
    const enlaceMapa = tieneCoordenadas
      ? `<a class="admin-pedido-mapa" href="https://www.google.com/maps?q=${encodeURIComponent(Number(pedido.lat))},${encodeURIComponent(Number(pedido.lng))}" target="_blank" rel="noopener">Ver en Google Maps</a>`
      : '';
    const direccionHtml = pedido.direccion
      ? `<p class="admin-pedido-dato"><span>Dirección</span>${PM.escaparHtml(pedido.direccion)}</p>${enlaceMapa}`
      : '<p class="admin-pedido-dato"><span>Dirección</span>Retiro en sucursal</p>';
    const whatsappHtml = telefono
      ? `<a class="btn-secundario admin-pedido-whatsapp" href="https://wa.me/${telefono}" target="_blank" rel="noopener">Abrir WhatsApp</a>`
      : '';
    const notasHtml = pedido.notas
      ? `<div class="admin-pedido-notas"><span>Notas</span><p>${PM.escaparHtml(pedido.notas)}</p></div>`
      : '';

    const pagoEstado = pedido.pagado === true ? 'Pagado' : 'Pago pendiente';
    const acciones = botonesPedido(pedido);

    const estado = ESTADOS_PEDIDO[pedido.estado] ? pedido.estado : 'desconocido';

    el.pedidoDetalleContenido.innerHTML = `
      <div class="admin-pedido-detalle-head">
        <span class="admin-pedido-estado estado-${estado}">${PM.escaparHtml(nombreEstadoPedido(pedido.estado))}</span>
        <span class="admin-pedido-hora">${PM.escaparHtml(fechaHoraPedido(pedido.created_at))}</span>
      </div>
      <div class="admin-pedido-detalle-grid">
        <p class="admin-pedido-dato"><span>Cliente</span>${PM.escaparHtml(pedido.cliente_nombre || 'Sin nombre')}</p>
        <p class="admin-pedido-dato"><span>Teléfono</span>${PM.escaparHtml(pedido.cliente_telefono || '-')}</p>
        <p class="admin-pedido-dato"><span>Modalidad</span>${PM.escaparHtml(etiquetaModalidadPedido(pedido.modalidad))}</p>
        <p class="admin-pedido-dato"><span>Sucursal</span>${PM.escaparHtml(nombreSucursalPedido(pedido.sucursal_id))}</p>
        <p class="admin-pedido-dato"><span>Pago</span>${PM.escaparHtml(pedido.metodo_pago || '-')} · ${PM.escaparHtml(pagoEstado)}</p>
      </div>
      ${direccionHtml}
      <div class="admin-pedido-items"><span class="admin-pedido-bloque-titulo">Ítems</span>${itemsHtml || '<p class="admin-ayuda">Sin ítems.</p>'}</div>
      ${notasHtml}
      <div class="admin-pedido-totales">
        <div><span>Subtotal</span><span>${formatearPrecio(pedido.subtotal)}</span></div>
        <div><span>Descuento</span><span>- ${formatearPrecio(pedido.descuento)}</span></div>
        <div><span>Envío</span><span>${formatearPrecio(pedido.costo_envio)}</span></div>
        <div class="admin-pedido-total"><span>Total</span><span>${formatearPrecio(pedido.total)}</span></div>
      </div>
      <div class="admin-pedido-acciones">${whatsappHtml}${acciones}</div>`;

    if (el.modalPedidoTitulo) {
      el.modalPedidoTitulo.textContent = `Pedido #${pedido.numero_orden || ''}`;
    }
  }

  function abrirDetallePedido(id) {
    const pedido = pedidos.find(item => String(item.id) === String(id));
    if (!pedido) return;
    pedidoAbiertoId = pedido.id;
    renderPedidoDetalle(pedido);
    if (el.modalPedido) el.modalPedido.hidden = false;
    document.body.classList.add('admin-modal-abierto');
  }

  function cerrarModalPedido() {
    pedidoAbiertoId = null;
    if (el.modalPedido) el.modalPedido.hidden = true;
    document.body.classList.remove('admin-modal-abierto');
  }

  function esErrorPermiso(error) {
    const mensaje = String((error && (error.message || error.error_description)) || '').toLowerCase();
    const codigo = String((error && error.code) || '');
    return codigo === '403' || codigo === '42501'
      || mensaje.includes('permission denied')
      || mensaje.includes('row-level security')
      || mensaje.includes('not authorized');
  }

  function errorEsDeSesion(error) {
    const mensaje = String((error && (error.message || error.error_description)) || '').toLowerCase();
    const codigo = String((error && error.code) || '');
    return codigo === '401' || codigo === '403' || codigo === 'PGRST301'
      || mensaje.includes('jwt') || mensaje.includes('permission')
      || mensaje.includes('row-level security') || mensaje.includes('sesión')
      || mensaje.includes('sesion') || mensaje.includes('no autorizado');
  }

  function mensajeErrorPedidos(error) {
    const detalle = (error && (error.message || error.error_description))
      ? String(error.message || error.error_description)
      : 'Error de conexión.';
    if (esErrorPermiso(error)) {
      return 'No tenés permiso para hacer esto.';
    }
    if (errorEsDeSesion(error)) {
      return `Tu sesión venció o no tenés permisos para ver los pedidos. Volvé a iniciar sesión. (${detalle})`;
    }
    return `No se pudieron cargar los pedidos: ${detalle}`;
  }

  async function cargarPedidos(opciones = {}) {
    if (!cliente || pedidosCargando) return;
    pedidosCargando = true;
    if (!opciones.silencioso) {
      mostrarEstadoPedidos('Cargando pedidos...');
      mostrarAvisoPedidos('');
    }

    try {
      const camposBase = 'id,numero_orden,created_at,sucursal_id,modalidad,estado,cliente_nombre,cliente_telefono,direccion,lat,lng,zona_envio,items_snapshot,subtotal,descuento,costo_envio,total,metodo_pago,notas';
      let respuesta = await cliente
        .from('pedidos')
        .select(`${camposBase},pagado,pagado_en`)
        .order('created_at', { ascending: false })
        .limit(500);

      if (respuesta.error) {
        const detalle = String(respuesta.error.message || '').toLowerCase();
        if (detalle.includes('pagado') && (detalle.includes('column') || detalle.includes('does not exist'))) {
          pedidosSoportaPagos = false;
          respuesta = await cliente
            .from('pedidos')
            .select(camposBase)
            .order('created_at', { ascending: false })
            .limit(500);
        }
      }

      const { data, error } = respuesta;
      if (error) throw error;

      pedidos = Array.isArray(data) ? data : [];
      pedidosCargados = true;
      renderPedidos();
      actualizarBadgePedidos();
      actualizarAlertaPedidos();

      if (pedidoAbiertoId) {
        const actual = pedidos.find(item => String(item.id) === String(pedidoAbiertoId));
        if (actual) renderPedidoDetalle(actual);
        else cerrarModalPedido();
      }

      if (adminRolError) aplicarAvisoRol();
      if (!opciones.silencioso) mostrarEstadoPedidos('Pedidos actualizados.', 'ok');
    } catch (error) {
      console.warn('No se pudieron cargar los pedidos:', error);
      mostrarEstadoPedidos('');
      mostrarAvisoPedidos(mensajeErrorPedidos(error), 'error');
    } finally {
      pedidosCargando = false;
    }
  }

  async function actualizarEstadoPedido(id, nuevoEstado, boton) {
    if (!cliente) {
      mostrarAvisoPedidos('Supabase no está disponible.', 'error');
      return;
    }

    const pedido = pedidos.find(item => String(item.id) === String(id));
    if (!pedido) return;

    if (boton) boton.disabled = true;
    try {
      const { data, error } = await cliente
        .from('pedidos')
        .update({ estado: nuevoEstado })
        .eq('id', id)
        .select('id,estado')
        .single();

      if (error) throw error;

      const indice = pedidos.findIndex(item => String(item.id) === String(id));
      if (indice >= 0) {
        pedidos[indice] = { ...pedidos[indice], estado: (data && data.estado) || nuevoEstado };
        actualizarTarjetaEnVista(pedidos[indice]);
      }
      actualizarBadgePedidos();
      actualizarAlertaPedidos();
      const actual = pedidos.find(item => String(item.id) === String(id));
      if (actual && String(pedidoAbiertoId) === String(id)) renderPedidoDetalle(actual);
      mostrarEstadoPedidos('Pedido actualizado.', 'ok');
      mostrarAvisoPedidos('');
    } catch (error) {
      console.warn('No se pudo actualizar el pedido:', error);
      mostrarAvisoPedidos(mensajeErrorPedidos(error), 'error');
    } finally {
      if (boton) boton.disabled = false;
    }
  }

  async function ejecutarAccionPedido(id, accion, boton) {
    if (!id || !accion) return;
    const pedido = pedidos.find(item => String(item.id) === String(id));
    if (!pedido) return;
    if (accion === 'avanzar') {
      const siguiente = siguienteEstadoPedido(pedido);
      if (siguiente) await actualizarEstadoPedido(id, siguiente, boton);
      return;
    }
    if (accion === 'cancelado') {
      if (!window.confirm('¿Cancelar este pedido?')) return;
      await actualizarEstadoPedido(id, 'cancelado', boton);
      return;
    }
    if (accion === 'pagado') {
      await marcarPedidoPagado(id, boton);
      return;
    }
    if (accion === 'imprimir') {
      imprimirPedido(id);
    }
  }

  async function marcarPedidoPagado(id, boton) {
    if (!cliente) {
      mostrarAvisoPedidos('Supabase no está disponible.', 'error');
      return;
    }
    if (!pedidosSoportaPagos) {
      mostrarAvisoPedidos('Aplicá la migración 016 para registrar pagos y nuevos estados.', 'error');
      return;
    }
    const pedido = pedidos.find(item => String(item.id) === String(id));
    if (!pedido || pedido.pagado === true) return;

    if (boton) boton.disabled = true;
    const pagadoEn = new Date().toISOString();
    try {
      const { data, error } = await cliente
        .from('pedidos')
        .update({ pagado: true, pagado_en: pagadoEn })
        .eq('id', id)
        .select('id,pagado,pagado_en')
        .single();
      if (error) throw error;

      const indice = pedidos.findIndex(item => String(item.id) === String(id));
      if (indice >= 0) {
        pedidos[indice] = {
          ...pedidos[indice],
          pagado: true,
          pagado_en: (data && data.pagado_en) || pagadoEn
        };
        actualizarTarjetaEnVista(pedidos[indice]);
        if (String(pedidoAbiertoId) === String(id)) renderPedidoDetalle(pedidos[indice]);
      }
      mostrarEstadoPedidos('Pedido marcado como pagado.', 'ok');
      mostrarAvisoPedidos('');
    } catch (error) {
      console.warn('No se pudo marcar el pedido como pagado:', error);
      mostrarAvisoPedidos(mensajeErrorPedidos(error), 'error');
    } finally {
      if (boton) boton.disabled = false;
    }
  }

  function imprimirPedido(id) {
    const pedido = pedidos.find(item => String(item.id) === String(id));
    if (!pedido || !el.pedidoTicket) return;
    const items = Array.isArray(pedido.items_snapshot) ? pedido.items_snapshot : [];
    const filas = items.map(item => {
      const cantidad = Number(item && item.cantidad) || 0;
      const nombre = PM.escaparHtml(item && item.nombre ? item.nombre : 'Producto');
      return `<tr><td>${cantidad}</td><td>${nombre}</td><td>${formatearPrecio(item && item.subtotal)}</td></tr>`;
    }).join('');
    const pagoEstado = pedido.pagado === true ? 'Pagado' : 'Pago pendiente';

    el.pedidoTicket.innerHTML = `
      <h1>Piedra Mora</h1>
      <p class="admin-ticket-numero">${PM.escaparHtml(pedido.numero_orden || 'Sin número')}</p>
      <p>${PM.escaparHtml(fechaHoraPedido(pedido.created_at))} · ${PM.escaparHtml(nombreSucursalPedido(pedido.sucursal_id))}</p>
      <p>${PM.escaparHtml(pedido.cliente_nombre || 'Sin nombre')} · ${PM.escaparHtml(pedido.cliente_telefono || '-')}</p>
      <p>${PM.escaparHtml(etiquetaModalidadPedido(pedido.modalidad))} · ${PM.escaparHtml(pedido.metodo_pago || '-')} · ${PM.escaparHtml(pagoEstado)}</p>
      ${pedido.direccion ? `<p>${PM.escaparHtml(pedido.direccion)}</p>` : ''}
      <table class="admin-ticket-tabla">
        <thead><tr><th>Cant.</th><th>Producto</th><th>Subtotal</th></tr></thead>
        <tbody>${filas || '<tr><td colspan="3">Sin ítems.</td></tr>'}</tbody>
      </table>
      <div class="admin-ticket-totales">
        <p><span>Subtotal</span><span>${formatearPrecio(pedido.subtotal)}</span></p>
        <p><span>Descuento</span><span>- ${formatearPrecio(pedido.descuento)}</span></p>
        <p><span>Envío</span><span>${formatearPrecio(pedido.costo_envio)}</span></p>
        <p class="admin-ticket-total"><span>Total</span><span>${formatearPrecio(pedido.total)}</span></p>
      </div>
      ${pedido.notas ? `<p class="admin-ticket-notas">Notas: ${PM.escaparHtml(pedido.notas)}</p>` : ''}`;

    document.body.classList.add('admin-imprimiendo-pedido');
    try {
      window.print();
    } finally {
      document.body.classList.remove('admin-imprimiendo-pedido');
    }
  }

  function campoCsv(valor) {
    let texto = String(valor === undefined || valor === null ? '' : valor);
    // Evita inyección de fórmulas al abrir en Excel/Sheets.
    if (/^[=+\-@\t\r]/.test(texto)) texto = "'" + texto;
    return `"${texto.replace(/"/g, '""')}"`;
  }

  function exportarPedidosCsv() {
    const lista = pedidosFiltrados();
    if (!lista.length) {
      mostrarAvisoPedidos('No hay pedidos para exportar con estos filtros.', 'info');
      return;
    }
    const encabezados = ['Numero', 'Fecha', 'Cliente', 'Telefono', 'Sucursal', 'Modalidad', 'Estado', 'Pago', 'Pagado', 'Subtotal', 'Descuento', 'Envio', 'Total', 'Items'];
    const filas = lista.map(pedido => {
      const items = Array.isArray(pedido.items_snapshot) ? pedido.items_snapshot : [];
      const resumen = items.map(item => `${Number(item && item.cantidad) || 0}x ${item && item.nombre ? item.nombre : 'Producto'}`).join(' | ');
      return [
        pedido.numero_orden || '',
        fechaHoraPedido(pedido.created_at),
        pedido.cliente_nombre || '',
        pedido.cliente_telefono || '',
        nombreSucursalPedido(pedido.sucursal_id),
        etiquetaModalidadPedido(pedido.modalidad),
        nombreEstadoPedido(pedido.estado),
        pedido.metodo_pago || '',
        pedido.pagado === true ? 'SI' : 'NO',
        pedido.subtotal,
        pedido.descuento,
        pedido.costo_envio,
        pedido.total,
        resumen
      ].map(campoCsv).join(';');
    });
    const contenido = '\uFEFF' + [encabezados.map(campoCsv).join(';'), ...filas].join('\r\n');
    const blob = new Blob([contenido], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const enlace = document.createElement('a');
    enlace.href = url;
    const rangoExportado = rangoPedidosActual();
    const nombreRango = rangoExportado.desde === rangoExportado.hasta
      ? rangoExportado.desde
      : `${rangoExportado.desde}-a-${rangoExportado.hasta}`;
    enlace.download = `pedidos-${nombreRango}.csv`;
    document.body.appendChild(enlace);
    enlace.click();
    enlace.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    mostrarEstadoPedidos('Pedidos exportados en CSV.', 'ok');
  }


  function cargarPreferenciasSonido() {
    try {
      const sonido = localStorage.getItem(CLAVE_PREF_SONIDO);
      if (sonido === 'off' || sonido === '0') pedidosSonidoActivo = false;
      if (sonido === 'on' || sonido === '1') pedidosSonidoActivo = true;
      const volumen = Number(localStorage.getItem(CLAVE_PREF_VOLUMEN));
      if (Number.isFinite(volumen)) {
        pedidosVolumen = Math.min(1, Math.max(0, volumen / 100));
      }
    } catch (error) {}
    if (el.pedidosVolumen) el.pedidosVolumen.value = String(Math.round(pedidosVolumen * 100));
  }

  function guardarPreferenciaSonido() {
    try {
      localStorage.setItem(CLAVE_PREF_SONIDO, pedidosSonidoActivo ? 'on' : 'off');
      localStorage.setItem(CLAVE_PREF_VOLUMEN, String(Math.round(pedidosVolumen * 100)));
    } catch (error) {}
  }

  function obtenerAudioContexto() {
    const ConstructorAudio = window.AudioContext || window.webkitAudioContext;
    if (!ConstructorAudio) return null;
    if (!audioContexto) audioContexto = new ConstructorAudio();
    return audioContexto;
  }

  async function desbloquearAudioPedidos() {
    const contexto = obtenerAudioContexto();
    if (!contexto) return false;
    try {
      if (contexto.state === 'suspended') await contexto.resume();
    } catch (error) {}
    audioDesbloqueado = contexto.state === 'running';
    actualizarEstadoSonido();
    return audioDesbloqueado;
  }

  function actualizarEstadoSonido() {
    const bloqueado = pedidosSonidoActivo && (!audioContexto || !audioDesbloqueado);
    if (el.pedidosSonidoEstado) {
      el.pedidosSonidoEstado.textContent = bloqueado
        ? 'Activá el sonido con un clic'
        : (pedidosSonidoActivo ? 'Sonido activo' : 'Sonido silenciado');
      el.pedidosSonidoEstado.dataset.tipo = bloqueado ? 'pendiente' : '';
    }
    if (el.btnPedidosActivarSonido) {
      el.btnPedidosActivarSonido.textContent = pedidosSonidoActivo ? 'Silenciar' : 'Activar sonido';
      el.btnPedidosActivarSonido.setAttribute('aria-pressed', pedidosSonidoActivo ? 'true' : 'false');
    }
  }

  function reproducirDingDong() {
    if (!pedidosSonidoActivo) return;
    const contexto = audioContexto;
    if (!contexto || !audioDesbloqueado || contexto.state !== 'running') {
      actualizarEstadoSonido();
      return;
    }
    try {
      const ahora = contexto.currentTime;
      const master = contexto.createGain();
      master.gain.setValueAtTime(Math.max(0.0001, pedidosVolumen), ahora);
      master.connect(contexto.destination);

      const notas = [
        { frecuencia: 783.99, inicio: 0, duracion: 0.45 },
        { frecuencia: 523.25, inicio: 0.32, duracion: 0.7 }
      ];

      notas.forEach(nota => {
        const oscilador = contexto.createOscillator();
        const ganancia = contexto.createGain();
        const inicio = ahora + nota.inicio;
        oscilador.type = 'sine';
        oscilador.frequency.setValueAtTime(nota.frecuencia, inicio);
        ganancia.gain.setValueAtTime(0.0001, inicio);
        ganancia.gain.exponentialRampToValueAtTime(0.24, inicio + 0.04);
        ganancia.gain.exponentialRampToValueAtTime(0.0001, inicio + nota.duracion);
        oscilador.connect(ganancia);
        ganancia.connect(master);
        oscilador.start(inicio);
        oscilador.stop(inicio + nota.duracion + 0.05);
      });
    } catch (error) {
      console.warn('No se pudo reproducir el sonido del pedido.', error);
    }
  }

  function actualizarTituloPedidos() {
    const nuevos = contarPedidosNuevos();
    if (nuevos > 0) {
      if (!pedidosTituloTimer) {
        pedidosTituloAlternado = false;
        pedidosTituloTimer = setInterval(() => {
          const cantidad = contarPedidosNuevos();
          if (cantidad <= 0) {
            actualizarTituloPedidos();
            return;
          }
          pedidosTituloAlternado = !pedidosTituloAlternado;
          document.title = pedidosTituloAlternado ? `(${cantidad}) Nuevo pedido` : pedidosTituloOriginal;
        }, 1200);
      }
      return;
    }
    if (pedidosTituloTimer) {
      clearInterval(pedidosTituloTimer);
      pedidosTituloTimer = null;
    }
    pedidosTituloAlternado = false;
    document.title = pedidosTituloOriginal;
  }

  function detenerAlertaPedidos() {
    if (pedidosAlertaTimer) {
      clearInterval(pedidosAlertaTimer);
      pedidosAlertaTimer = null;
    }
    actualizarTituloPedidos();
  }

  function actualizarAlertaPedidos() {
    const hayNuevos = contarPedidosNuevos() > 0;
    if (hayNuevos && pedidosSonidoActivo) {
      if (!pedidosAlertaTimer) {
        pedidosAlertaTimer = setInterval(() => {
          if (contarPedidosNuevos() > 0 && pedidosSonidoActivo) reproducirDingDong();
          else actualizarAlertaPedidos();
        }, INTERVALO_ALERTA_PEDIDOS);
      }
    } else if (pedidosAlertaTimer) {
      clearInterval(pedidosAlertaTimer);
      pedidosAlertaTimer = null;
    }
    actualizarTituloPedidos();
    actualizarEstadoSonido();
  }

  function alertarPedidoNuevo() {
    if (pedidosSonidoActivo) {
      desbloquearAudioPedidos().then(desbloqueado => {
        if (desbloqueado) reproducirDingDong();
      }).catch(() => {});
    }
    actualizarAlertaPedidos();
  }

  async function alternarSonidoPedidos() {
    pedidosSonidoActivo = !pedidosSonidoActivo;
    guardarPreferenciaSonido();
    if (pedidosSonidoActivo) {
      const desbloqueado = await desbloquearAudioPedidos();
      if (desbloqueado) reproducirDingDong();
    }
    actualizarAlertaPedidos();
  }

  function cambiarVolumenPedidos(evento) {
    const valor = Number(evento && evento.target ? evento.target.value : 70);
    pedidosVolumen = Number.isFinite(valor) ? Math.min(1, Math.max(0, valor / 100)) : 0.7;
    guardarPreferenciaSonido();
    if (pedidosSonidoActivo && audioDesbloqueado) reproducirDingDong();
  }

  function manejarPedidoInsertado(payload) {
    const nuevo = payload && payload.new;
    if (!nuevo || !nuevo.id) return;

    const existe = pedidos.some(item => String(item.id) === String(nuevo.id));
    if (!existe) {
      pedidos.unshift(nuevo);
      if (pedidos.length > 500) pedidos.length = 500;
      if (pedidoVisiblePorRol(nuevo)) {
        alertarPedidoNuevo();
        mostrarAvisoPedidos(`Nuevo pedido #${nuevo.numero_orden || ''}.`, 'info');
      }
    }

    actualizarTarjetaEnVista(nuevo);
    actualizarBadgePedidos();
  }

  function manejarPedidoActualizado(payload) {
    const actualizado = payload && payload.new;
    if (!actualizado || !actualizado.id) return;

    const indice = pedidos.findIndex(item => String(item.id) === String(actualizado.id));
    if (indice >= 0) {
      const estadoAnterior = pedidos[indice].estado;
      pedidos[indice] = { ...pedidos[indice], ...actualizado };
      actualizarTarjetaEnVista(pedidos[indice]);
      actualizarBadgePedidos();
      actualizarAlertaPedidos();
      if (String(pedidoAbiertoId) === String(actualizado.id)) {
        renderPedidoDetalle(pedidos[indice]);
      }
      if (estadoAnterior !== actualizado.estado) mostrarEstadoPedidos('Pedido actualizado.', 'ok');
    } else {
      cargarPedidos({ silencioso: true });
    }
  }

  function iniciarRealtimePedidos() {
    if (!cliente || pedidosCanal) return;
    pedidosCanal = cliente
      .channel('admin-pedidos')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'pedidos' }, manejarPedidoInsertado)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'pedidos' }, manejarPedidoActualizado)
      .subscribe((estado) => {
        if (estado === 'SUBSCRIBED') {
          if (el.pedidosAviso && el.pedidosAviso.dataset.tipo === 'error') mostrarAvisoPedidos('');
        } else if (estado === 'CHANNEL_ERROR' || estado === 'TIMED_OUT' || estado === 'CLOSED') {
          mostrarAvisoPedidos('El tiempo real no está disponible. Usá "Actualizar" o esperá el refresco automático.', 'error');
        }
      });
  }

  function detenerRealtimePedidos() {
    if (pedidosCanal && cliente) {
      try {
        if (typeof cliente.removeChannel === 'function') cliente.removeChannel(pedidosCanal);
        else pedidosCanal.unsubscribe();
      } catch (error) {
        console.warn(error);
      }
    }
    pedidosCanal = null;
    if (pedidosTimer) {
      clearInterval(pedidosTimer);
      pedidosTimer = null;
    }
  }

  function iniciarRefrescoPedidos() {
    if (pedidosTimer) return;
    pedidosTimer = setInterval(() => {
      if (!cliente || !el.panel || el.panel.hidden) return;
      cargarPedidos({ silencioso: true });
    }, 60000);
  }

  /* ===== Agotados por sucursal ===== */

  function mostrarEstadoAgotados(texto, tipo = '') {
    mostrarEstado(el.agotadosEstado, texto, tipo);
  }

  function mostrarAvisoAgotados(texto, tipo = 'info', accion = null) {
    if (!el.agotadosAviso) return;
    if (agotadosAvisoTimer) {
      clearTimeout(agotadosAvisoTimer);
      agotadosAvisoTimer = null;
    }
    if (!texto) {
      el.agotadosAviso.hidden = true;
      el.agotadosAviso.textContent = '';
      return;
    }
    el.agotadosAviso.hidden = false;
    el.agotadosAviso.dataset.tipo = tipo;
    el.agotadosAviso.textContent = texto;
    if (accion) {
      const boton = document.createElement('button');
      boton.type = 'button';
      boton.className = 'btn-secundario admin-agotados-deshacer';
      boton.textContent = accion.texto;
      boton.addEventListener('click', () => {
        mostrarAvisoAgotados('');
        accion.alClick();
      });
      el.agotadosAviso.append(' ', boton);
      agotadosAvisoTimer = setTimeout(() => mostrarAvisoAgotados(''), 8000);
    }
  }

  function agotadosDeSucursal(sucursalId) {
    return agotadosPorSucursal.get(String(sucursalId)) || new Set();
  }

  function estaAgotadoEn(sucursalId, productoId) {
    return agotadosDeSucursal(sucursalId).has(String(productoId));
  }

  function fijarAgotado(sucursalId, productoId, agotado) {
    const sid = String(sucursalId);
    if (!agotadosPorSucursal.has(sid)) agotadosPorSucursal.set(sid, new Set());
    const set = agotadosPorSucursal.get(sid);
    if (agotado) set.add(String(productoId));
    else set.delete(String(productoId));
  }

  function renderAgotadosTodo() {
    renderAgotados();
    renderDisponibilidadCarta();
  }

  function poblarSelectAgotados() {
    if (!el.agotadosSucursal) return;
    if (el.agotadosSucursalCampo) el.agotadosSucursalCampo.hidden = esAdminSucursal();
    if (esAdminSucursal()) {
      el.agotadosSucursal.disabled = true;
      if (!adminSucursalId) {
        el.agotadosSucursal.innerHTML = '<option value="">Sin sucursal asignada</option>';
        el.agotadosSucursal.value = '';
        return;
      }
      const nombre = SUCURSALES_NOMBRES[adminSucursalId] || adminSucursalId;
      el.agotadosSucursal.innerHTML = `<option value="${escaparHtml(adminSucursalId)}">${escaparHtml(nombre)}</option>`;
      el.agotadosSucursal.value = adminSucursalId;
      return;
    }
    el.agotadosSucursal.disabled = false;
    const actual = el.agotadosSucursal.value;
    const opciones = Object.keys(SUCURSALES_NOMBRES)
      .sort((a, b) => SUCURSALES_NOMBRES[a].localeCompare(SUCURSALES_NOMBRES[b], 'es'))
      .map(id => `<option value="${escaparHtml(id)}">${escaparHtml(SUCURSALES_NOMBRES[id])}</option>`)
      .join('');
    el.agotadosSucursal.innerHTML = opciones;
    if (actual) el.agotadosSucursal.value = actual;
  }

  function sucursalAgotadosSeleccionada() {
    if (esAdminSucursal()) return adminSucursalId || '';
    return (el.agotadosSucursal && el.agotadosSucursal.value) || '';
  }

  function productosCartaDeSucursal(sucursalId) {
    if (!carta || !Array.isArray(carta.productos) || !sucursalId) return [];
    return carta.productos
      .filter(producto => Array.isArray(producto.sucursales) && producto.sucursales.includes(sucursalId))
      .sort((a, b) => {
        const categoriaA = nombreCategoria(a.categoria);
        const categoriaB = nombreCategoria(b.categoria);
        if (categoriaA !== categoriaB) return categoriaA.localeCompare(categoriaB, 'es');
        return String(a.nombre || '').localeCompare(String(b.nombre || ''), 'es');
      });
  }

  function normalizarBusquedaAgotados(texto) {
    return String(texto || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
  }

  function poblarCategoriasAgotados(productos) {
    if (!el.agotadosCategoria) return;
    const actual = el.agotadosCategoria.value;
    const ids = [...new Set(productos.map(p => p.categoria))];
    ids.sort((x, y) => nombreCategoria(x).localeCompare(nombreCategoria(y), 'es'));
    el.agotadosCategoria.innerHTML = '<option value="">Todas las categorías</option>'
      + ids.map(id => `<option value="${escaparHtml(id)}">${escaparHtml(nombreCategoria(id))}</option>`).join('');
    el.agotadosCategoria.value = ids.includes(actual) ? actual : '';
  }

  function renderAgotados() {
    if (!el.agotadosLista) return;
    const scrollPrevio = el.agotadosLista.scrollTop;
    const sucursalId = sucursalAgotadosSeleccionada();
    if (!sucursalId) {
      el.agotadosLista.innerHTML = '<p class="admin-envios-vacio">Sin sucursal asignada. Recargá la página o pedile al dueño que asigne una sucursal.</p>';
      return;
    }

    const productos = productosCartaDeSucursal(sucursalId);
    if (!productos.length) {
      el.agotadosLista.innerHTML = '<p class="admin-envios-vacio">No hay productos cargados para esta sucursal.</p>';
      return;
    }

    const agotados = agotadosDeSucursal(sucursalId);
    poblarCategoriasAgotados(productos);
    const cantidad = productos.filter(p => agotados.has(String(p.id))).length;
    if (el.agotadosResumen) el.agotadosResumen.textContent = `${cantidad} ${cantidad === 1 ? 'agotado' : 'agotados'}`;
    if (el.agotadosFiltroEstado) el.agotadosFiltroEstado.value = agotadosFiltroEstado;

    const consulta = normalizarBusquedaAgotados(el.agotadosBuscar && el.agotadosBuscar.value);
    const categoria = el.agotadosCategoria ? el.agotadosCategoria.value : '';
    const filtrados = productos.filter(p => {
      const id = String(p.id);
      if (categoria && p.categoria !== categoria) return false;
      if (consulta && !normalizarBusquedaAgotados(p.nombre || p.id).includes(consulta)) return false;
      if (agotadosSaliendo.has(id)) return true;
      if (agotadosFiltroEstado === 'no-disponibles') return agotados.has(id);
      if (agotadosFiltroEstado === 'disponibles') return !agotados.has(id);
      return true;
    });
    if (agotadosFiltroEstado === 'todos') {
      // Agotados primero; el resto conserva el orden por categoría/nombre.
      filtrados.sort((x, y) => Number(agotados.has(String(y.id))) - Number(agotados.has(String(x.id))));
    }

    if (!filtrados.length) {
      if (agotadosFiltroEstado === 'no-disponibles' && cantidad === 0 && !consulta && !categoria) {
        el.agotadosLista.innerHTML = '<div class="admin-envios-vacio admin-agotados-vacio"><p>No hay productos agotados</p><button type="button" class="btn-secundario" data-agotados-ver-todos>Ver todos para marcar</button></div>';
      } else {
        el.agotadosLista.innerHTML = '<p class="admin-envios-vacio">No hay productos que coincidan.</p>';
      }
      return;
    }

    const sucursalNombre = SUCURSALES_NOMBRES[sucursalId] || sucursalId;
    el.agotadosLista.innerHTML = filtrados.map(producto => {
      const id = String(producto.id);
      const agotado = agotados.has(id);
      const guardando = agotadosGuardando.has(`${sucursalId}|${id}`);
      const nombre = producto.nombre || id;
      return `<div class="admin-agotado-fila${agotado ? ' es-agotado' : ''}${agotadosSaliendo.has(id) ? ' saliendo' : ''}">
        <span class="admin-agotado-texto">
          <strong>${escaparHtml(nombre)}</strong>
          <small>${escaparHtml(nombreCategoria(producto.categoria))}</small>
        </span>
        <span class="admin-agotado-estado">${agotado ? 'Agotado' : 'Disponible'}</span>
        <button type="button" class="admin-switch" role="switch" aria-checked="${agotado ? 'true' : 'false'}" aria-label="${escaparHtml(`${nombre} en ${sucursalNombre}`)}" data-agotado-id="${escaparHtml(id)}" data-agotado-sucursal="${escaparHtml(sucursalId)}"${guardando ? ' disabled' : ''}><span class="admin-switch-perilla"></span></button>
      </div>`;
    }).join('');
    el.agotadosLista.scrollTop = scrollPrevio;
  }

  // Carga una sola vez las filas de todas las sucursales que el usuario puede ver (la RLS filtra).
  async function cargarAgotados(opciones = {}) {
    if (!cliente || agotadosCargando) return;
    if (!carta) await cargarCarta();

    agotadosCargando = true;
    if (!opciones.silencioso) {
      mostrarEstadoAgotados('Cargando agotados...');
      mostrarAvisoAgotados('');
    }

    try {
      const { data, error } = await cliente
        .from('agotados_sucursal')
        .select('producto_id,sucursal_id');
      if (error) throw error;

      const nuevo = new Map();
      (Array.isArray(data) ? data : []).forEach(item => {
        if (!item || !item.producto_id || !item.sucursal_id) return;
        const sid = String(item.sucursal_id);
        if (!nuevo.has(sid)) nuevo.set(sid, new Set());
        nuevo.get(sid).add(String(item.producto_id));
      });
      agotadosPorSucursal = nuevo;
      agotadosCargados = true;
      renderAgotadosTodo();
      mostrarEstadoAgotados('');
    } catch (error) {
      console.warn('No se pudieron cargar los agotados:', error);
      mostrarEstadoAgotados('');
      mostrarAvisoAgotados(esErrorPermiso(error) ? 'No tenés permiso para hacer esto.' : `No se pudieron cargar los agotados: ${error.message || 'error de conexión'}`, 'error');
    } finally {
      agotadosCargando = false;
    }
  }

  // Guardado instantáneo compartido por Pedidos y la carta del admin.
  async function cambiarAgotado(productoId, sucursalId, marcar, opciones = {}) {
    const id = String(productoId || '');
    const sid = String(sucursalId || '');
    const clave = `${sid}|${id}`;
    if (!cliente || !id || !sid || agotadosGuardando.has(clave)) return;
    agotadosGuardando.add(clave);
    const conTransicion = !marcar && opciones.origen === 'pedidos' && agotadosFiltroEstado === 'no-disponibles';
    if (conTransicion) agotadosSaliendo.add(id);
    fijarAgotado(sid, id, marcar);
    renderAgotadosTodo();
    mostrarAvisoAgotados('');
    if (conTransicion) {
      setTimeout(() => {
        agotadosSaliendo.delete(id);
        renderAgotados();
      }, 250);
    }

    try {
      let error = null;
      if (marcar) {
        const respuesta = await cliente
          .from('agotados_sucursal')
          .upsert({ producto_id: id, sucursal_id: sid }, { onConflict: 'producto_id,sucursal_id' });
        error = respuesta.error;
      } else {
        const respuesta = await cliente
          .from('agotados_sucursal')
          .delete()
          .eq('producto_id', id)
          .eq('sucursal_id', sid);
        error = respuesta.error;
      }
      if (error) throw error;
      if (!marcar && opciones.origen === 'pedidos') {
        const producto = buscarProducto(id);
        const nombre = (producto && producto.nombre) || id;
        mostrarAvisoAgotados(`Reactivado: ${nombre}.`, 'info', {
          texto: 'Deshacer',
          alClick: () => cambiarAgotado(id, sid, true, { origen: 'pedidos' })
        });
      }
    } catch (error) {
      console.warn('No se pudo cambiar el agotado:', error);
      // Revierte el switch.
      fijarAgotado(sid, id, !marcar);
      agotadosSaliendo.delete(id);
      mostrarEstadoAgotados('');
      mostrarAvisoAgotados(esErrorPermiso(error) ? 'No tenés permiso para hacer esto.' : `No se pudo guardar el agotado: ${error.message || 'error de conexión'}`, 'error');
    } finally {
      agotadosGuardando.delete(clave);
      renderAgotadosTodo();
    }
  }

  const SUCURSALES_CORTO = { 'intendente-lascano': 'Lascano', 'maestro-quiroga': 'Maestro Quiroga' };
  const SUCURSALES_SWITCH = { 'intendente-lascano': 'Int. Lascano', 'maestro-quiroga': 'Maestro Quiroga' };

  function htmlDisponibilidadProducto(producto) {
    const id = String(producto.id);
    const sucursales = (Array.isArray(producto.sucursales) ? producto.sucursales : [])
      .map(String)
      .filter(sid => SUCURSALES_NOMBRES[sid] || SUCURSALES_SWITCH[sid]);
    if (!sucursales.length) return '';
    sucursales.sort((a, b) => (SUCURSALES_SWITCH[a] || a).localeCompare(SUCURSALES_SWITCH[b] || b, 'es'));

    const etiquetas = [];
    if (PM.productoEstaAgotado(producto)) etiquetas.push('Agotado en todas');
    sucursales.forEach(sid => {
      if (estaAgotadoEn(sid, id)) etiquetas.push(`Agotado en ${SUCURSALES_CORTO[sid] || SUCURSALES_NOMBRES[sid] || sid}`);
    });
    const chips = etiquetas.map(t => `<span class="admin-badge admin-badge-agotado">${escaparHtml(t)}</span>`).join('');

    const filas = sucursales.map(sid => {
      const agotado = estaAgotadoEn(sid, id);
      const guardando = agotadosGuardando.has(`${sid}|${id}`);
      const sucNombre = SUCURSALES_SWITCH[sid] || SUCURSALES_NOMBRES[sid] || sid;
      const prodNombre = producto.nombre || id;
      return `<div class="admin-disp-fila${agotado ? ' es-agotado' : ''}">
        <span class="admin-disp-nombre">${escaparHtml(sucNombre)}</span>
        <span class="admin-agotado-estado">${agotado ? 'Agotado' : 'Disponible'}</span>
        <button type="button" class="admin-switch" role="switch" aria-checked="${agotado ? 'true' : 'false'}" aria-label="${escaparHtml(`${prodNombre} en ${sucNombre}`)}" data-agotado-carta="${escaparHtml(id)}" data-agotado-sucursal="${escaparHtml(sid)}"${guardando ? ' disabled' : ''}><span class="admin-switch-perilla"></span></button>
      </div>`;
    }).join('');

    return `<p class="admin-disp-titulo">Disponibilidad</p>${chips ? `<div class="admin-disp-chips">${chips}</div>` : ''}${filas}`;
  }

  // Actualiza solo los bloques de disponibilidad (no toca los editores abiertos).
  function renderDisponibilidadCarta() {
    if (!el.listaProductos) return;
    el.listaProductos.querySelectorAll('[data-disponibilidad]').forEach(cont => {
      const producto = buscarProducto(cont.dataset.disponibilidad);
      if (producto) cont.innerHTML = htmlDisponibilidadProducto(producto);
    });
  }

  function programarRecargaAgotados() {
    if (agotadosRealtimeTimer) clearTimeout(agotadosRealtimeTimer);
    agotadosRealtimeTimer = setTimeout(() => {
      agotadosRealtimeTimer = null;
      if (agotadosCargados) cargarAgotados({ silencioso: true });
    }, 300);
  }

  function iniciarRealtimeAgotados() {
    if (!cliente || agotadosCanal) return;
    agotadosCanal = cliente
      .channel('admin-agotados')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'agotados_sucursal' }, programarRecargaAgotados)
      .subscribe((estado) => {
        if (estado === 'CHANNEL_ERROR' || estado === 'TIMED_OUT') {
          console.warn('Realtime de agotados no disponible:', estado);
        }
      });
  }

  function detenerRealtimeAgotados() {
    if (agotadosCanal && cliente) {
      try {
        if (typeof cliente.removeChannel === 'function') cliente.removeChannel(agotadosCanal);
        else agotadosCanal.unsubscribe();
      } catch (error) {
        console.warn(error);
      }
    }
    agotadosCanal = null;
    if (agotadosRealtimeTimer) {
      clearTimeout(agotadosRealtimeTimer);
      agotadosRealtimeTimer = null;
    }
  }

  /* ===== Fase 1: seccion Envios ===== */

  function mostrarEstadoEnvios(texto, tipo = '') {
    mostrarEstado(el.enviosEstado, texto, tipo);
  }

  function mostrarAvisoEnvios(texto, tipo = 'info') {
    if (!el.enviosAviso) return;
    if (!texto) {
      el.enviosAviso.hidden = true;
      el.enviosAviso.textContent = '';
      return;
    }
    el.enviosAviso.hidden = false;
    el.enviosAviso.dataset.tipo = tipo;
    el.enviosAviso.textContent = texto;
  }

  function mensajeErrorEnvios(error, accion) {
    const detalle = (error && (error.message || error.error_description))
      ? String(error.message || error.error_description)
      : 'Error de conexión.';
    if (esErrorPermiso(error)) {
      return 'No tenés permiso para hacer esto.';
    }
    if (errorEsDeSesion(error)) {
      return `Tu sesión venció o no tenés permisos para ${accion || 'editar'} envíos. Volvé a iniciar sesión. (${detalle})`;
    }
    return `No se pudieron ${accion || 'cargar'} los envíos: ${detalle}`;
  }

  function etiquetaSucursalEnvios(id) {
    if (!id) return 'Todas';
    return SUCURSALES_NOMBRES[id] || id;
  }

  function poblarSelectSucursalesEnvios() {
    if (!el.tramoSucursal) return;
    if (esAdminSucursal()) {
      el.tramoSucursal.disabled = true;
      if (!adminSucursalId) {
        el.tramoSucursal.innerHTML = '<option value="">Sin sucursal asignada</option>';
        el.tramoSucursal.value = '';
        return;
      }
      const nombre = SUCURSALES_NOMBRES[adminSucursalId] || adminSucursalId;
      el.tramoSucursal.innerHTML = `<option value="${escaparHtml(adminSucursalId)}">${escaparHtml(nombre)}</option>`;
      el.tramoSucursal.value = adminSucursalId;
      return;
    }
    el.tramoSucursal.disabled = false;
    const actual = el.tramoSucursal.value;
    const opciones = Object.keys(SUCURSALES_NOMBRES)
      .sort((a, b) => SUCURSALES_NOMBRES[a].localeCompare(SUCURSALES_NOMBRES[b], 'es'))
      .map(id => `<option value="${escaparHtml(id)}">${escaparHtml(SUCURSALES_NOMBRES[id])}</option>`)
      .join('');
    el.tramoSucursal.innerHTML = `<option value="">Todas</option>${opciones}`;
    if (actual) el.tramoSucursal.value = actual;
  }

  function numeroConfig(valor, porDefecto = null) {
    if (valor === null || valor === undefined || valor === '') return porDefecto;
    const numero = Number(valor);
    return Number.isFinite(numero) ? numero : porDefecto;
  }

  function renderConfigEnvios() {
    if (el.enviosMetrosCuadra) el.enviosMetrosCuadra.value = String(configEnvios.metrosPorCuadra || 100);
    if (el.enviosTiempoEstimado) {
      el.enviosTiempoEstimado.value = configEnvios.tiempoEstimado ? String(configEnvios.tiempoEstimado) : '';
    }
    if (el.enviosDescuentoEfectivo) el.enviosDescuentoEfectivo.value = String(configEnvios.descuentos.efectivo || 0);
    if (el.enviosDescuentoTransferencia) {
      el.enviosDescuentoTransferencia.value = String(configEnvios.descuentos.transferencia || 0);
    }
    if (el.enviosAyuda) {
      const metros = configEnvios.metrosPorCuadra || 100;
      el.enviosAyuda.textContent = `La distancia se mide en línea recta desde la sucursal. Una cuadra cuenta como ${metros} metros.`;
    }
    if (el.tramosMetrosReferencia) {
      const metros = configEnvios.metrosPorCuadra || 100;
      el.tramosMetrosReferencia.textContent = `1 cuadra = ${metros} metros.`;
    }
  }

  function renderZonasNormales() {
    if (!el.zonasNormalesLista) return;
    const visibles = zonasNormales.filter(zona => sucursalVisibleParaRol(zona.sucursal_id));
    if (!visibles.length) {
      el.zonasNormalesLista.innerHTML = '<p class="admin-envios-vacio">No hay filas de Zona normal. Revisá la configuración de zonas en la base.</p>';
      return;
    }

    el.zonasNormalesLista.innerHTML = visibles.map(zona => {
      const id = escaparHtml(zona.id);
      const editable = puedeEditarFilaSucursal(zona.sucursal_id);
      return `<div class="admin-envios-zona${editable ? '' : ' admin-solo-lectura'}" data-zona-id="${id}">
        <div class="admin-envios-zona-nombre">
          <strong>${escaparHtml(zona.nombre || 'Zona normal')}</strong>
          <small>${escaparHtml(etiquetaSucursalEnvios(zona.sucursal_id))}</small>
        </div>
        <label class="admin-campo">
          <span>Costo base</span>
          <input type="number" min="0" step="1" inputmode="decimal" data-zona-costo value="${Number(zona.costo) || 0}"${editable ? '' : ' disabled'}>
        </label>
        <label class="admin-campo admin-campo-check">
          <input type="checkbox" data-zona-tramos ${zona.aplica_tramos ? 'checked' : ''}${editable ? '' : ' disabled'}>
          <span>Usar tramos</span>
        </label>
        <label class="admin-campo admin-campo-check">
          <input type="checkbox" data-zona-activa ${zona.activa ? 'checked' : ''}${editable ? '' : ' disabled'}>
          <span>Activa</span>
        </label>
        ${editable ? '<button type="button" class="btn-primario" data-zona-guardar>Guardar</button>' : '<span class="admin-chip">Solo lectura</span>'}
      </div>`;
    }).join('');
  }

  function renderTramosEnvios() {
    if (!el.tramosLista) return;
    const visibles = tramosEnvios.filter(tramo => sucursalVisibleParaRol(tramo.sucursal_id));
    if (!visibles.length) {
      el.tramosLista.innerHTML = '<p class="admin-envios-vacio">Todavía no hay tramos cargados.</p>';
      return;
    }

    const ordenados = [...visibles].sort((a, b) => {
      const sa = a.sucursal_id || '';
      const sb = b.sucursal_id || '';
      if (sa !== sb) {
        if (!sa) return -1;
        if (!sb) return 1;
        return sa.localeCompare(sb, 'es');
      }
      return Number(a.desde_cuadras) - Number(b.desde_cuadras);
    });

    el.tramosLista.innerHTML = ordenados.map(tramo => {
      const id = escaparHtml(tramo.id);
      const activa = !!tramo.activa;
      const editable = puedeEditarFilaSucursal(tramo.sucursal_id);
      const acciones = editable
        ? `<button type="button" class="btn-secundario" data-tramo-accion="editar">Editar</button>
          <button type="button" class="btn-secundario" data-tramo-accion="toggle">${activa ? 'Desactivar' : 'Activar'}</button>
          <button type="button" class="btn-peligro" data-tramo-accion="eliminar">Borrar</button>`
        : '<span class="admin-chip">Solo lectura</span>';
      return `<div class="admin-envios-tramo ${activa ? '' : 'inactivo'}${editable ? '' : ' admin-solo-lectura'}" data-tramo-id="${id}">
        <div class="admin-envios-tramo-dato">
          <small>Sucursal</small>
          <span>${escaparHtml(etiquetaSucursalEnvios(tramo.sucursal_id))}</span>
        </div>
        <div class="admin-envios-tramo-dato">
          <small>Desde</small>
          <span>${Number(tramo.desde_cuadras) || 0} cuadras</span>
        </div>
        <div class="admin-envios-tramo-dato">
          <small>Hasta</small>
          <span>${Number(tramo.hasta_cuadras) || 0} cuadras</span>
        </div>
        <div class="admin-envios-tramo-dato">
          <small>Costo</small>
          <span>${formatearPrecio(tramo.costo)}</span>
        </div>
        <div class="admin-envios-tramo-acciones">
          <span class="admin-envios-tramo-badge ${activa ? 'activa' : 'inactiva'}">${activa ? 'Activo' : 'Inactivo'}</span>
          ${acciones}
        </div>
      </div>`;
    }).join('');
  }

  async function cargarEnvios(opciones = {}) {
    if (!cliente || enviosCargando) return;
    enviosCargando = true;
    if (!opciones.silencioso) {
      mostrarEstadoEnvios('Cargando envíos...');
      mostrarAvisoEnvios('');
    }

    try {
      const [configResp, tramosResp, zonasResp] = await Promise.all([
        cliente
          .from('config_negocio')
          .select('clave,valor')
          .in('clave', ['metros_por_cuadra', 'tiempo_estimado_entrega', 'descuentos_pago']),
        cliente
          .from('tramos_envio')
          .select('id,sucursal_id,desde_cuadras,hasta_cuadras,costo,activa'),
        cliente
          .from('zonas_envio')
          .select('id,sucursal_id,nombre,costo,activa,aplica_tramos')
          .ilike('nombre', 'Zona normal')
      ]);

      if (configResp.error) throw configResp.error;
      if (tramosResp.error) throw tramosResp.error;
      if (zonasResp.error) throw zonasResp.error;

      const filasConfig = Array.isArray(configResp.data) ? configResp.data : [];
      const valorClave = (clave) => {
        const fila = filasConfig.find(item => item && item.clave === clave);
        return fila ? fila.valor : null;
      };

      const descuentos = valorClave('descuentos_pago');
      configEnvios = {
        metrosPorCuadra: numeroConfig(valorClave('metros_por_cuadra'), 100),
        tiempoEstimado: numeroConfig(valorClave('tiempo_estimado_entrega'), null),
        descuentos: {
          efectivo: numeroConfig(descuentos && descuentos.efectivo, 0),
          transferencia: numeroConfig(descuentos && descuentos.transferencia, 0)
        }
      };

      tramosEnvios = Array.isArray(tramosResp.data) ? tramosResp.data : [];
      zonasNormales = Array.isArray(zonasResp.data) ? zonasResp.data : [];

      renderConfigEnvios();
      renderZonasNormales();
      renderTramosEnvios();
      enviosCargados = true;

      if (adminRolError) aplicarAvisoRol();
      if (!opciones.silencioso) {
        mostrarEstadoEnvios('Envíos actualizados.', 'ok');
        mostrarAvisoEnvios(avisoHuecoFinalTodas(), 'info');
      }
    } catch (error) {
      console.warn('No se pudieron cargar los envíos:', error);
      mostrarEstadoEnvios('');
      mostrarAvisoEnvios(mensajeErrorEnvios(error, 'cargar'), 'error');
    } finally {
      enviosCargando = false;
    }
  }

  async function guardarConfigEnvios(evento) {
    if (evento) evento.preventDefault();
    if (!cliente) {
      mostrarAvisoEnvios('Supabase no está disponible.', 'error');
      return;
    }
    if (esAdminSucursal()) {
      mostrarAvisoEnvios('No tenés permiso para editar la configuración general.', 'error');
      return;
    }

    const metros = Number(el.enviosMetrosCuadra && el.enviosMetrosCuadra.value);
    if (!Number.isInteger(metros) || metros < 50 || metros > 300) {
      mostrarAvisoEnvios('Los metros por cuadra deben ser un número entero entre 50 y 300.', 'error');
      return;
    }

    const tiempoTexto = el.enviosTiempoEstimado ? String(el.enviosTiempoEstimado.value).trim() : '';
    const tiempo = tiempoTexto === '' ? null : Number(tiempoTexto);
    if (tiempo !== null && (!Number.isInteger(tiempo) || tiempo < 1)) {
      mostrarAvisoEnvios('El tiempo estimado debe ser un número entero de minutos mayor a cero, o quedar vacío.', 'error');
      return;
    }

    const efectivo = Number(el.enviosDescuentoEfectivo && el.enviosDescuentoEfectivo.value);
    const transferencia = Number(el.enviosDescuentoTransferencia && el.enviosDescuentoTransferencia.value);
    if (!Number.isFinite(efectivo) || efectivo < 0 || efectivo > 100
      || !Number.isFinite(transferencia) || transferencia < 0 || transferencia > 100) {
      mostrarAvisoEnvios('Los descuentos deben ser números entre 0 y 100.', 'error');
      return;
    }

    if (el.btnGuardarConfigEnvios) el.btnGuardarConfigEnvios.disabled = true;
    try {
      const filas = [
        { clave: 'metros_por_cuadra', valor: metros },
        { clave: 'descuentos_pago', valor: { efectivo, transferencia } }
      ];
      if (tiempo !== null) filas.push({ clave: 'tiempo_estimado_entrega', valor: tiempo });

      const { error } = await cliente.from('config_negocio').upsert(filas, { onConflict: 'clave' });
      if (error) throw error;

      if (tiempo === null) {
        const { error: errorTiempo } = await cliente
          .from('config_negocio')
          .delete()
          .eq('clave', 'tiempo_estimado_entrega');
        if (errorTiempo) throw errorTiempo;
      }

      configEnvios = {
        metrosPorCuadra: metros,
        tiempoEstimado: tiempo,
        descuentos: { efectivo, transferencia }
      };
      renderConfigEnvios();
      mostrarAvisoEnvios('');
      mostrarEstadoEnvios('Configuración guardada.', 'ok');
    } catch (error) {
      console.warn('No se pudo guardar la configuración de envíos:', error);
      mostrarAvisoEnvios(mensajeErrorEnvios(error, 'guardar'), 'error');
    } finally {
      if (el.btnGuardarConfigEnvios) el.btnGuardarConfigEnvios.disabled = false;
    }
  }

  async function guardarZonaNormal(id) {
    if (!cliente || !id) return;
    const contenedor = el.zonasNormalesLista
      ? el.zonasNormalesLista.querySelector(`[data-zona-id="${id}"]`)
      : null;
    if (!contenedor) return;

    const zona = zonasNormales.find(item => String(item.id) === String(id));
    if (!zona || !puedeEditarFilaSucursal(zona.sucursal_id)) {
      if (el.zonasNormalesEstado) mostrarEstado(el.zonasNormalesEstado, 'No tenés permiso para hacer esto.', 'error');
      return;
    }

    const costoInput = contenedor.querySelector('[data-zona-costo]');
    const tramosInput = contenedor.querySelector('[data-zona-tramos]');
    const activaInput = contenedor.querySelector('[data-zona-activa]');
    const costo = Number(costoInput && costoInput.value);

    if (!Number.isFinite(costo) || costo < 0) {
      if (el.zonasNormalesEstado) mostrarEstado(el.zonasNormalesEstado, 'El costo base debe ser un número mayor o igual a 0.', 'error');
      return;
    }

    const boton = contenedor.querySelector('[data-zona-guardar]');
    if (boton) boton.disabled = true;
    try {
      const { error } = await cliente
        .from('zonas_envio')
        .update({
          costo,
          aplica_tramos: !!(tramosInput && tramosInput.checked),
          activa: !!(activaInput && activaInput.checked)
        })
        .eq('id', id);

      if (error) throw error;
      if (el.zonasNormalesEstado) mostrarEstado(el.zonasNormalesEstado, 'Costo base guardado.', 'ok');
      await cargarEnvios({ silencioso: true });
    } catch (error) {
      console.warn('No se pudo guardar la zona normal:', error);
      if (el.zonasNormalesEstado) mostrarEstado(el.zonasNormalesEstado, mensajeErrorEnvios(error, 'guardar'), 'error');
    } finally {
      if (boton) boton.disabled = false;
    }
  }

  function abrirFormTramo(tramo) {
    if (!el.formTramo) return;
    el.formTramo.hidden = false;
    if (el.tramoId) el.tramoId.value = tramo && tramo.id ? tramo.id : '';
    if (el.tramoSucursal) {
      const sucursalTramo = tramo && tramo.sucursal_id ? tramo.sucursal_id : '';
      el.tramoSucursal.value = esAdminSucursal() && adminSucursalId ? adminSucursalId : sucursalTramo;
    }
    if (el.tramoDesde) el.tramoDesde.value = tramo ? String(tramo.desde_cuadras) : '';
    if (el.tramoHasta) el.tramoHasta.value = tramo ? String(tramo.hasta_cuadras) : '';
    if (el.tramoCosto) el.tramoCosto.value = tramo ? String(tramo.costo) : '';
    if (el.tramoActiva) el.tramoActiva.checked = tramo ? !!tramo.activa : true;
    if (el.btnGuardarTramo) el.btnGuardarTramo.textContent = tramo ? 'Guardar cambios' : 'Guardar tramo';
    if (el.tramoEstado) mostrarEstado(el.tramoEstado, '');
    if (el.tramoDesde) el.tramoDesde.focus();
  }

  function cerrarFormTramo() {
    if (!el.formTramo) return;
    el.formTramo.hidden = true;
    if (el.tramoId) el.tramoId.value = '';
    if (el.tramoDesde) el.tramoDesde.value = '';
    if (el.tramoHasta) el.tramoHasta.value = '';
    if (el.tramoCosto) el.tramoCosto.value = '';
    if (el.tramoActiva) el.tramoActiva.checked = true;
    if (el.tramoEstado) mostrarEstado(el.tramoEstado, '');
  }

  function validarTramo(datos, idExcluir) {
    if (!Number.isInteger(datos.desde_cuadras) || datos.desde_cuadras < 0) {
      throw new Error('Desde debe ser un número entero mayor o igual a 0.');
    }
    if (!Number.isInteger(datos.hasta_cuadras) || datos.hasta_cuadras < 0) {
      throw new Error('Hasta debe ser un número entero mayor o igual a 0.');
    }
    if (datos.hasta_cuadras < datos.desde_cuadras) {
      throw new Error('Hasta debe ser mayor o igual que Desde.');
    }
    if (!Number.isFinite(datos.costo) || datos.costo < 0) {
      throw new Error('El costo debe ser un número mayor o igual a 0.');
    }

    if (!datos.activa) return;

    const clave = datos.sucursal_id || '';
    const otros = tramosEnvios.filter(tramo => {
      if (String(tramo.id) === String(idExcluir)) return false;
      if (!tramo.activa) return false;
      const claveTramo = tramo.sucursal_id || '';
      if (!clave) return true;
      return !claveTramo || claveTramo === clave;
    });

    const choque = otros.find(tramo =>
      datos.desde_cuadras <= Number(tramo.hasta_cuadras)
      && datos.hasta_cuadras >= Number(tramo.desde_cuadras)
    );

    if (choque) {
      throw new Error(`El tramo de ${datos.desde_cuadras} a ${datos.hasta_cuadras} cuadras se superpone con el tramo activo de ${choque.desde_cuadras} a ${choque.hasta_cuadras} cuadras de ${etiquetaSucursalEnvios(choque.sucursal_id)}.`);
    }
  }

  function avisoHuecoFinal(sucursalId) {
    const clave = sucursalId || '';
    const activos = tramosEnvios.filter(tramo => tramo.activa && (tramo.sucursal_id || '') === clave);
    if (!activos.length) return '';
    const maximo = Math.max(...activos.map(tramo => Number(tramo.hasta_cuadras) || 0));
    if (maximo >= 999) return '';
    return `Aviso: el último tramo activo llega hasta ${maximo} cuadras. Conviene que llegue a 999 para no dejar envíos sin precio.`;
  }

  function avisoHuecoFinalTodas() {
    const conHueco = [];
    Object.keys(SUCURSALES_NOMBRES).forEach(id => {
      const activos = tramosEnvios.filter(tramo =>
        tramo.activa && (!tramo.sucursal_id || tramo.sucursal_id === id));
      if (!activos.length) return;
      const maximo = Math.max(...activos.map(tramo => Number(tramo.hasta_cuadras) || 0));
      if (maximo < 999) {
        conHueco.push(`${SUCURSALES_NOMBRES[id]} (hasta ${maximo} cuadras)`);
      }
    });
    if (!conHueco.length) return '';
    return `Aviso: el último tramo activo no llega a 999 cuadras en ${conHueco.join(', ')}. Conviene que llegue a 999 para no dejar envíos sin precio.`;
  }

  async function guardarTramo(evento) {
    if (evento) evento.preventDefault();
    if (!cliente) {
      mostrarAvisoEnvios('Supabase no está disponible.', 'error');
      return;
    }

    const id = el.tramoId ? el.tramoId.value : '';
    const datos = {
      sucursal_id: el.tramoSucursal && el.tramoSucursal.value ? el.tramoSucursal.value : null,
      desde_cuadras: Number(el.tramoDesde && el.tramoDesde.value),
      hasta_cuadras: Number(el.tramoHasta && el.tramoHasta.value),
      costo: Number(el.tramoCosto && el.tramoCosto.value),
      activa: !!(el.tramoActiva && el.tramoActiva.checked)
    };

    if (esAdminSucursal()) {
      const existente = id ? tramosEnvios.find(item => String(item.id) === String(id)) : null;
      if (!adminSucursalId || (existente && !puedeEditarFilaSucursal(existente.sucursal_id))) {
        if (el.tramoEstado) mostrarEstado(el.tramoEstado, 'No tenés permiso para hacer esto.', 'error');
        return;
      }
      datos.sucursal_id = adminSucursalId;
    }

    try {
      validarTramo(datos, id);
    } catch (error) {
      if (el.tramoEstado) mostrarEstado(el.tramoEstado, error.message, 'error');
      return;
    }

    if (el.btnGuardarTramo) el.btnGuardarTramo.disabled = true;
    try {
      let respuesta;
      if (id) {
        respuesta = await cliente.from('tramos_envio').update(datos).eq('id', id);
      } else {
        respuesta = await cliente.from('tramos_envio').insert(datos);
      }
      if (respuesta.error) throw respuesta.error;

      cerrarFormTramo();
      await cargarEnvios({ silencioso: true });
      mostrarEstadoEnvios(id ? 'Tramo actualizado.' : 'Tramo agregado.', 'ok');
      mostrarAvisoEnvios(avisoHuecoFinal(datos.sucursal_id), 'info');
    } catch (error) {
      console.warn('No se pudo guardar el tramo:', error);
      if (el.tramoEstado) mostrarEstado(el.tramoEstado, mensajeErrorEnvios(error, 'guardar'), 'error');
    } finally {
      if (el.btnGuardarTramo) el.btnGuardarTramo.disabled = false;
    }
  }

  async function toggleTramo(id) {
    if (!cliente) return;
    const tramo = tramosEnvios.find(item => String(item.id) === String(id));
    if (!tramo) return;
    if (!puedeEditarFilaSucursal(tramo.sucursal_id)) {
      mostrarAvisoEnvios('No tenés permiso para hacer esto.', 'error');
      return;
    }

    const actualizado = { ...tramo, activa: !tramo.activa };
    if (actualizado.activa) {
      try {
        validarTramo({
          sucursal_id: actualizado.sucursal_id,
          desde_cuadras: Number(actualizado.desde_cuadras),
          hasta_cuadras: Number(actualizado.hasta_cuadras),
          costo: Number(actualizado.costo),
          activa: true
        }, id);
      } catch (error) {
        mostrarAvisoEnvios(error.message, 'error');
        return;
      }
    }

    try {
      const { error } = await cliente
        .from('tramos_envio')
        .update({ activa: actualizado.activa })
        .eq('id', id);
      if (error) throw error;

      await cargarEnvios({ silencioso: true });
      mostrarEstadoEnvios(actualizado.activa ? 'Tramo activado.' : 'Tramo desactivado.', 'ok');
      mostrarAvisoEnvios(avisoHuecoFinal(actualizado.sucursal_id), 'info');
    } catch (error) {
      console.warn('No se pudo cambiar el estado del tramo:', error);
      mostrarAvisoEnvios(mensajeErrorEnvios(error, 'actualizar'), 'error');
    }
  }

  async function eliminarTramo(id) {
    if (!cliente) return;
    const tramo = tramosEnvios.find(item => String(item.id) === String(id));
    if (!tramo) return;
    if (!puedeEditarFilaSucursal(tramo.sucursal_id)) {
      mostrarAvisoEnvios('No tenés permiso para hacer esto.', 'error');
      return;
    }
    if (!window.confirm(`¿Borrar el tramo de ${tramo.desde_cuadras} a ${tramo.hasta_cuadras} cuadras de ${etiquetaSucursalEnvios(tramo.sucursal_id)}?`)) return;

    try {
      const { error } = await cliente.from('tramos_envio').delete().eq('id', id);
      if (error) throw error;
      await cargarEnvios({ silencioso: true });
      mostrarEstadoEnvios('Tramo borrado.', 'ok');
      mostrarAvisoEnvios('');
    } catch (error) {
      console.warn('No se pudo borrar el tramo:', error);
      mostrarAvisoEnvios(mensajeErrorEnvios(error, 'borrar'), 'error');
    }
  }

  // ---------------------------------------------------------------
  // Cupones (solo dueño). El servidor valida todo: acá solo se muestra.
  // ---------------------------------------------------------------
  const ZONA_AR = 'America/Argentina/Buenos_Aires';

  function puedeVerCupones() {
    return adminRol === 'dueno' && !adminRolError;
  }

  function mostrarEstadoCupones(texto, tipo = '') {
    mostrarEstado(el.cuponesEstado, texto, tipo);
  }

  function mostrarAvisoCupones(texto, tipo = 'info') {
    if (!el.cuponesAviso) return;
    if (!texto) {
      el.cuponesAviso.hidden = true;
      el.cuponesAviso.textContent = '';
      return;
    }
    el.cuponesAviso.hidden = false;
    el.cuponesAviso.dataset.tipo = tipo;
    el.cuponesAviso.textContent = texto;
  }

  function formatearFechaCupon(iso) {
    if (!iso) return '';
    const fecha = new Date(iso);
    if (Number.isNaN(fecha.getTime())) return '';
    return new Intl.DateTimeFormat('es-AR', {
      timeZone: ZONA_AR, day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit', hour12: false
    }).format(fecha);
  }

  // timestamptz -> valor de <input type="datetime-local"> en hora Argentina.
  function isoAInputLocal(iso) {
    if (!iso) return '';
    const fecha = new Date(iso);
    if (Number.isNaN(fecha.getTime())) return '';
    const partes = {};
    new Intl.DateTimeFormat('en-CA', {
      timeZone: ZONA_AR, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
    }).formatToParts(fecha).forEach(p => { partes[p.type] = p.value; });
    return `${partes.year}-${partes.month}-${partes.day}T${partes.hour}:${partes.minute}`;
  }

  // Valor de datetime-local (hora Argentina) -> ISO con offset -03:00.
  function inputLocalAIso(valor) {
    const limpio = String(valor || '').trim();
    if (!limpio) return null;
    return `${limpio.length === 16 ? `${limpio}:00` : limpio}-03:00`;
  }

  function vigenciaCupon(cupon) {
    const desde = formatearFechaCupon(cupon.fecha_inicio);
    const hasta = formatearFechaCupon(cupon.fecha_vencimiento);
    if (!desde && !hasta) return 'Sin límite';
    if (desde && hasta) return `${desde} → ${hasta}`;
    return desde ? `Desde ${desde}` : `Hasta ${hasta}`;
  }

  function valorCupon(cupon) {
    const valor = Number(cupon.valor);
    return cupon.tipo === 'porcentaje' ? `${valor}%` : formatearPrecio(valor);
  }

  // Prioridad: pausado > vencido > agotado > programado > activo.
  // Se comparan instantes con la hora del navegador; el servidor decide la validez real.
  function estadoCupon(cupon, usos) {
    if (!cupon.activo) return 'pausado';
    const ahora = new Date();
    if (cupon.fecha_vencimiento && new Date(cupon.fecha_vencimiento) < ahora) return 'vencido';
    if (cupon.usos_maximos_total !== null && cupon.usos_maximos_total !== undefined
      && usos >= Number(cupon.usos_maximos_total)) return 'agotado';
    if (cupon.fecha_inicio && new Date(cupon.fecha_inicio) > ahora) return 'programado';
    return 'activo';
  }

  const ETIQUETA_ESTADO_CUPON = {
    activo: 'Activo', pausado: 'Pausado', vencido: 'Vencido', agotado: 'Agotado', programado: 'Programado'
  };

  function resumenUsosCupon(cuponId) {
    const id = String(cuponId);
    let cantidad = 0;
    let total = 0;
    cuponesUsos.forEach(uso => {
      if (String(uso.cupon_id) !== id) return;
      const pedido = Array.isArray(uso.pedidos) ? uso.pedidos[0] : uso.pedidos;
      if (pedido && pedido.estado === 'cancelado') return;
      cantidad += 1;
      total += Number(uso.monto_descontado) || 0;
    });
    return { cantidad, total };
  }

  function mensajeErrorCupones(error, accion) {
    if (esErrorPermiso(error)) return 'No tenés permiso para hacer esto.';
    const codigo = String((error && error.code) || '');
    const detalle = String((error && (error.message || error.error_description)) || 'Error de conexión.');
    if (codigo === '23505') return 'Ya existe un cupón con ese código.';
    if (codigo === '23503') return 'Tiene usos registrados: pausalo en vez de borrarlo.';
    if (codigo === '23514') {
      if (detalle.includes('cupones_valor_porcentaje_chk')) return 'El porcentaje no puede superar 100.';
      if (detalle.includes('cupones_valor_chk')) return 'El valor tiene que ser mayor a 0.';
      if (detalle.includes('cupones_fechas_chk')) return 'El vencimiento no puede ser anterior al inicio.';
      if (detalle.includes('cupones_usos_')) return 'Los usos máximos tienen que ser números enteros, 0 o más.';
      if (detalle.includes('cupones_compra_minima_chk')) return 'La compra mínima no puede ser negativa.';
      if (detalle.includes('cupones_codigo')) return 'El código tiene que tener entre 1 y 40 caracteres, en mayúsculas y sin espacios.';
      return `Algún dato no cumple las reglas del cupón. (${detalle})`;
    }
    return `No se pudo ${accion || 'cargar'} el cupón: ${detalle}`;
  }

  function renderCupones() {
    if (!el.cuponesLista) return;
    if (!cuponesLista.length) {
      el.cuponesLista.innerHTML = '<p class="admin-envios-vacio">Todavía no hay cupones cargados.</p>';
      return;
    }
    el.cuponesLista.innerHTML = cuponesLista.map(cupon => {
      const { cantidad, total } = resumenUsosCupon(cupon.id);
      const estado = estadoCupon(cupon, cantidad);
      const max = cupon.usos_maximos_total === null || cupon.usos_maximos_total === undefined
        ? '∞' : String(Number(cupon.usos_maximos_total));
      return `<div class="admin-cupon-fila ${escaparHtml(estado)}" data-cupon-id="${escaparHtml(cupon.id)}">
        <div class="admin-envios-tramo-dato">
          <small>Código</small>
          <span>${escaparHtml(cupon.codigo)}</span>
        </div>
        <div class="admin-envios-tramo-dato">
          <small>Descuento</small>
          <span>${escaparHtml(valorCupon(cupon))}</span>
        </div>
        <div class="admin-envios-tramo-dato">
          <small>Estado</small>
          <span><span class="admin-cupon-badge ${escaparHtml(estado)}">${escaparHtml(ETIQUETA_ESTADO_CUPON[estado])}</span></span>
        </div>
        <div class="admin-envios-tramo-dato">
          <small>Vigencia</small>
          <span>${escaparHtml(vigenciaCupon(cupon))}</span>
        </div>
        <div class="admin-envios-tramo-dato">
          <small>Usos · Descontado</small>
          <span>${cantidad} / ${escaparHtml(max)} · ${escaparHtml(formatearPrecio(total))}</span>
        </div>
        <div class="admin-envios-tramo-acciones">
          <button type="button" class="btn-secundario" data-cupon-accion="editar">Editar</button>
          <button type="button" class="btn-secundario" data-cupon-accion="toggle">${cupon.activo ? 'Pausar' : 'Activar'}</button>
          <button type="button" class="btn-peligro" data-cupon-accion="eliminar">Borrar</button>
        </div>
      </div>`;
    }).join('');
  }

  async function cargarCupones(opciones = {}) {
    if (!cliente || cuponesCargando || !puedeVerCupones()) return;
    cuponesCargando = true;
    if (!opciones.silencioso) {
      mostrarEstadoCupones('Cargando cupones...');
      mostrarAvisoCupones('');
    }
    try {
      const cuponesResp = await cliente
        .from('cupones')
        .select('*')
        .order('creado_en', { ascending: false });
      if (cuponesResp.error) throw cuponesResp.error;

      let usosResp = await cliente
        .from('cupon_usos')
        .select('cupon_id, monto_descontado, pedidos(estado)');
      let sinEstado = false;
      if (usosResp.error) {
        console.warn('No se pudo traer el estado de los pedidos de los usos:', usosResp.error);
        usosResp = await cliente.from('cupon_usos').select('cupon_id, monto_descontado');
        sinEstado = true;
      }
      if (usosResp.error) throw usosResp.error;

      cuponesLista = cuponesResp.data || [];
      cuponesUsos = usosResp.data || [];
      cuponesCargados = true;
      renderCupones();
      mostrarEstadoCupones('');
      mostrarAvisoCupones(sinEstado
        ? 'No se pudo leer el estado de los pedidos: los usos y el total descontado incluyen pedidos cancelados.'
        : '', 'info');
    } catch (error) {
      console.warn('No se pudieron cargar los cupones:', error);
      mostrarEstadoCupones('');
      mostrarAvisoCupones(mensajeErrorCupones(error, 'cargar'), 'error');
    } finally {
      cuponesCargando = false;
    }
  }

  function actualizarEtiquetaValorCupon() {
    if (!el.cuponValorEtiqueta || !el.cuponTipo) return;
    el.cuponValorEtiqueta.textContent = el.cuponTipo.value === 'porcentaje'
      ? 'Valor (1 a 100)' : 'Valor en pesos (mayor a 0)';
  }

  function abrirFormCupon(cupon) {
    if (!el.formCupon) return;
    el.formCupon.hidden = false;
    const editando = !!cupon;
    const nulo = valor => (valor === null || valor === undefined ? '' : Number(valor));
    const unico = lista => (Array.isArray(lista) && lista.length === 1 ? lista[0] : '');
    el.cuponId.value = editando ? cupon.id : '';
    el.cuponCodigo.value = editando ? cupon.codigo : '';
    el.cuponCodigo.disabled = editando;
    el.cuponTipo.value = editando ? cupon.tipo : 'porcentaje';
    el.cuponValor.value = editando ? Number(cupon.valor) : '';
    el.cuponCompraMinima.value = editando && Number(cupon.compra_minima) ? Number(cupon.compra_minima) : '';
    el.cuponFechaInicio.value = editando ? isoAInputLocal(cupon.fecha_inicio) : '';
    el.cuponFechaVencimiento.value = editando ? isoAInputLocal(cupon.fecha_vencimiento) : '';
    el.cuponUsosTotal.value = editando ? nulo(cupon.usos_maximos_total) : '';
    el.cuponUsosCliente.value = editando ? nulo(cupon.usos_por_cliente) : '';
    el.cuponSucursales.value = editando ? unico(cupon.sucursales_permitidas) : '';
    el.cuponModalidades.value = editando ? unico(cupon.modalidades_permitidas) : '';
    el.cuponActivo.checked = editando ? !!cupon.activo : true;
    el.cuponPrimeraCompra.checked = editando ? !!cupon.primera_compra : false;
    el.cuponAcumulable.checked = editando ? !!cupon.acumulable_con_pago : false;
    if (el.cuponNotaUsos) {
      el.cuponNotaUsos.hidden = !(editando && resumenUsosCupon(cupon.id).cantidad > 0);
    }
    mostrarEstado(el.cuponFormEstado, '');
    if (el.cuponFormTitulo) el.cuponFormTitulo.textContent = editando ? 'Editar cupón' : 'Nuevo cupón';
    actualizarEtiquetaValorCupon();
    el.formCupon.scrollIntoView({ behavior: 'smooth', block: 'start' });
    (editando ? el.cuponValor : el.cuponCodigo).focus({ preventScroll: true });
  }

  function cerrarFormCupon() {
    if (!el.formCupon) return;
    el.formCupon.hidden = true;
    mostrarEstado(el.cuponFormEstado, '');
    if (el.cuponesLista) el.cuponesLista.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function enteroOpcional(valor) {
    const texto = String(valor || '').trim();
    if (texto === '') return { vacio: true };
    const n = Number(texto);
    return { vacio: false, n, ok: Number.isInteger(n) && n >= 0 };
  }

  async function guardarCupon(evento) {
    evento.preventDefault();
    if (!cliente || !puedeVerCupones()) return;
    const fallo = mensaje => { mostrarEstado(el.cuponFormEstado, mensaje, 'error'); };

    const id = el.cuponId.value;
    const codigo = el.cuponCodigo.value.replace(/\s+/g, '').toUpperCase();
    if (!id) {
      if (!codigo) return fallo('Escribí un código.');
      if (codigo.length > 40) return fallo('El código no puede tener más de 40 caracteres.');
    }

    const tipo = el.cuponTipo.value;
    const valor = Number(el.cuponValor.value);
    if (!Number.isFinite(valor) || valor <= 0) return fallo('El valor tiene que ser mayor a 0.');
    if (tipo === 'porcentaje' && (valor < 1 || valor > 100)) return fallo('El porcentaje tiene que estar entre 1 y 100.');
    if (tipo === 'monto_fijo' && !Number.isInteger(valor)) return fallo('El monto fijo tiene que ser en pesos enteros.');

    const compra = String(el.cuponCompraMinima.value).trim() === '' ? 0 : Number(el.cuponCompraMinima.value);
    if (!Number.isFinite(compra) || compra < 0) return fallo('La compra mínima no puede ser negativa.');

    const total = enteroOpcional(el.cuponUsosTotal.value);
    const porCliente = enteroOpcional(el.cuponUsosCliente.value);
    if (!total.vacio && !total.ok) return fallo('Los usos máximos totales tienen que ser un entero, 0 o más.');
    if (!porCliente.vacio && !porCliente.ok) return fallo('Los usos por cliente tienen que ser un entero, 0 o más.');

    const inicio = inputLocalAIso(el.cuponFechaInicio.value);
    const vence = inputLocalAIso(el.cuponFechaVencimiento.value);
    if (inicio && Number.isNaN(new Date(inicio).getTime())) return fallo('La fecha de inicio no es válida.');
    if (vence && Number.isNaN(new Date(vence).getTime())) return fallo('La fecha de vencimiento no es válida.');
    if (inicio && vence && new Date(vence) < new Date(inicio)) return fallo('El vencimiento no puede ser anterior al inicio.');

    const datos = {
      tipo,
      valor,
      activo: el.cuponActivo.checked,
      fecha_inicio: inicio,
      fecha_vencimiento: vence,
      usos_maximos_total: total.vacio ? null : total.n,
      usos_por_cliente: porCliente.vacio ? null : porCliente.n,
      compra_minima: compra,
      primera_compra: el.cuponPrimeraCompra.checked,
      sucursales_permitidas: el.cuponSucursales.value ? [el.cuponSucursales.value] : null,
      modalidades_permitidas: el.cuponModalidades.value ? [el.cuponModalidades.value] : null,
      acumulable_con_pago: el.cuponAcumulable.checked
    };

    el.btnGuardarCupon.disabled = true;
    mostrarEstado(el.cuponFormEstado, 'Guardando...');
    try {
      const consulta = id
        ? cliente.from('cupones').update(datos).eq('id', id)
        : cliente.from('cupones').insert({ ...datos, codigo });
      const { error: errorGuardar } = await consulta;
      if (errorGuardar) throw errorGuardar;
      cerrarFormCupon();
      await cargarCupones({ silencioso: true });
      mostrarEstadoCupones(id ? 'Cupón actualizado.' : 'Cupón creado.', 'ok');
    } catch (errorGuardar) {
      console.warn('No se pudo guardar el cupón:', errorGuardar);
      mostrarEstado(el.cuponFormEstado, mensajeErrorCupones(errorGuardar, 'guardar'), 'error');
    } finally {
      el.btnGuardarCupon.disabled = false;
    }
  }

  async function alternarCupon(id) {
    const cupon = cuponesLista.find(item => String(item.id) === String(id));
    if (!cupon || !cliente || !puedeVerCupones()) return;
    try {
      const { error } = await cliente.from('cupones').update({ activo: !cupon.activo }).eq('id', id);
      if (error) throw error;
      await cargarCupones({ silencioso: true });
      mostrarEstadoCupones(cupon.activo ? 'Cupón pausado.' : 'Cupón activado.', 'ok');
    } catch (error) {
      console.warn('No se pudo cambiar el estado del cupón:', error);
      mostrarAvisoCupones(mensajeErrorCupones(error, 'actualizar'), 'error');
    }
  }

  async function borrarCupon(id) {
    const cupon = cuponesLista.find(item => String(item.id) === String(id));
    if (!cupon || !cliente || !puedeVerCupones()) return;
    const usos = resumenUsosCupon(id).cantidad;
    const aviso = usos > 0
      ? `El cupón ${cupon.codigo} tiene ${usos} uso(s) registrado(s). Con historial no se puede borrar: mejor pausalo. ¿Intentar borrarlo igual?`
      : `¿Borrar el cupón ${cupon.codigo}? No se puede deshacer.`;
    if (!window.confirm(aviso)) return;
    try {
      const { error } = await cliente.from('cupones').delete().eq('id', id);
      if (error) throw error;
      await cargarCupones({ silencioso: true });
      mostrarEstadoCupones('Cupón borrado.', 'ok');
      mostrarAvisoCupones('');
    } catch (error) {
      console.warn('No se pudo borrar el cupón:', error);
      mostrarAvisoCupones(mensajeErrorCupones(error, 'borrar'), 'error');
    }
  }

  // ---------------------------------------------------------------
  // Fidelidad (solo dueño). Reglas espejo de pm_fidelidad_config (019);
  // el servidor es la autoridad: si la config es inválida, el programa queda inactivo.
  // ---------------------------------------------------------------
  const FIDELIDAD_MAX_NIVELES = 20;

  function puedeVerFidelidad() {
    return adminRol === 'dueno' && !adminRolError;
  }

  function mostrarAvisoFidelidad(texto, tipo = 'info') {
    if (!el.fidelidadAviso) return;
    if (!texto) {
      el.fidelidadAviso.hidden = true;
      el.fidelidadAviso.textContent = '';
      return;
    }
    el.fidelidadAviso.hidden = false;
    el.fidelidadAviso.dataset.tipo = tipo;
    el.fidelidadAviso.textContent = texto;
  }

  // Texto de un input -> entero >= 0, o null si no es un entero válido.
  function enteroFidelidad(valor) {
    const texto = String(valor === null || valor === undefined ? '' : valor).trim();
    return /^\d{1,9}$/.test(texto) ? Number(texto) : null;
  }

  function numeroFidelidad(valor) {
    const texto = String(valor === null || valor === undefined ? '' : valor).trim();
    if (texto === '') return null;
    const numero = Number(texto);
    return Number.isFinite(numero) ? numero : null;
  }

  function nivelFidelidadVacio() {
    return { en: '', tipo: 'descuento_porcentaje', valor: '', tope: '', producto: '', dias: '30' };
  }

  // Config guardada (jsonb) -> valores crudos del formulario, sin descartar nada legible.
  function formularioDesdeConfigFidelidad(cfg) {
    const texto = (v) => (v === null || v === undefined || typeof v === 'object' ? '' : String(v));
    const base = cfg && typeof cfg === 'object' && !Array.isArray(cfg) ? cfg : {};
    const niveles = Array.isArray(base.niveles) ? base.niveles : [];
    return {
      activo: base.activo === true,
      pedidoMinimo: texto(base.pedido_minimo),
      ciclo: texto(base.ciclo),
      niveles: niveles.map(n => {
        const nivel = n && typeof n === 'object' ? n : {};
        return {
          en: texto(nivel.en),
          tipo: nivel.tipo === 'producto_gratis' ? 'producto_gratis' : 'descuento_porcentaje',
          valor: texto(nivel.valor),
          tope: texto(nivel.tope_en_pesos),
          producto: texto(nivel.producto_id),
          dias: texto(nivel.dias_vencimiento)
        };
      })
    };
  }

  // Valida valores crudos del formulario. Devuelve { error } o { config }.
  function validarFidelidad(datos) {
    const minimo = enteroFidelidad(datos.pedidoMinimo);
    if (minimo === null) return { error: 'El pedido mínimo tiene que ser un número entero de pesos, 0 o más.' };

    const ciclo = enteroFidelidad(datos.ciclo);
    if (ciclo === null || ciclo < 1 || ciclo > 1000) return { error: 'El ciclo tiene que ser un número entero entre 1 y 1000.' };

    if (!datos.niveles.length) return { error: 'Tiene que haber al menos un nivel.' };
    if (datos.niveles.length > FIDELIDAD_MAX_NIVELES) return { error: `Pueden ser como máximo ${FIDELIDAD_MAX_NIVELES} niveles.` };

    const usados = new Set();
    const niveles = [];
    for (let i = 0; i < datos.niveles.length; i++) {
      const n = datos.niveles[i];
      const pref = `Nivel ${i + 1}:`;

      const en = enteroFidelidad(n.en);
      if (en === null || en < 1 || en > ciclo) return { error: `${pref} el número de pedido ("en") tiene que ser un entero entre 1 y ${ciclo}.` };
      if (usados.has(en)) return { error: `${pref} el pedido nº ${en} está repetido en otro nivel.` };
      usados.add(en);

      const dias = enteroFidelidad(n.dias);
      if (dias === null || dias < 1 || dias > 365) return { error: `${pref} los días de vencimiento tienen que ser un entero entre 1 y 365.` };

      if (n.tipo === 'descuento_porcentaje') {
        const valor = numeroFidelidad(n.valor);
        if (valor === null || valor <= 0 || valor > 100) return { error: `${pref} el porcentaje tiene que ser mayor a 0 y hasta 100.` };
        let tope = null;
        if (String(n.tope).trim() !== '') {
          tope = numeroFidelidad(n.tope);
          if (tope === null || tope <= 0) return { error: `${pref} el tope en pesos tiene que ser mayor a 0, o quedar vacío.` };
        }
        niveles.push({ en, tipo: 'descuento_porcentaje', valor, tope_en_pesos: tope, dias_vencimiento: dias });
      } else if (n.tipo === 'producto_gratis') {
        const producto = String(n.producto || '').trim();
        if (producto.length < 1 || producto.length > 80) return { error: `${pref} elegí el producto a regalar.` };
        niveles.push({ en, tipo: 'producto_gratis', producto_id: producto, dias_vencimiento: dias });
      } else {
        return { error: `${pref} el tipo no es válido.` };
      }
    }

    niveles.sort((a, b) => a.en - b.en);
    return {
      config: { activo: datos.activo === true, pedido_minimo: minimo, ciclo, niveles }
    };
  }

  function opcionesProductoFidelidad(seleccionado) {
    const productos = carta && Array.isArray(carta.productos) ? carta.productos.filter(p => p && p.id) : [];
    const ordenados = productos.slice().sort((a, b) => String(a.nombre || a.id).localeCompare(String(b.nombre || b.id), 'es'));
    let html = `<option value="">Elegí un producto</option>`;
    let encontrado = !seleccionado;
    ordenados.forEach(p => {
      if (String(p.id) === seleccionado) encontrado = true;
      html += `<option value="${escaparHtml(p.id)}"${String(p.id) === seleccionado ? ' selected' : ''}>${escaparHtml(p.nombre || p.id)}</option>`;
    });
    if (!encontrado) {
      html += `<option value="${escaparHtml(seleccionado)}" selected>${escaparHtml(seleccionado)} (no está en la carta)</option>`;
    }
    return html;
  }

  function htmlNivelFidelidad(nivel, indice, total) {
    const esPorc = nivel.tipo !== 'producto_gratis';
    return `<div class="admin-fidelidad-nivel" data-fidelidad-nivel>
      <label class="admin-campo">
        <span>Nivel ${indice + 1}: en el pedido nº</span>
        <input type="number" min="1" max="1000" step="1" inputmode="numeric" data-campo="en" value="${escaparHtml(nivel.en)}">
      </label>
      <label class="admin-campo">
        <span>Tipo</span>
        <select data-campo="tipo">
          <option value="descuento_porcentaje"${esPorc ? ' selected' : ''}>Descuento (%)</option>
          <option value="producto_gratis"${esPorc ? '' : ' selected'}>Producto gratis</option>
        </select>
      </label>
      <label class="admin-campo" data-grupo="porcentaje"${esPorc ? '' : ' hidden'}>
        <span>Valor (%)</span>
        <input type="number" min="1" max="100" step="1" inputmode="decimal" data-campo="valor" value="${escaparHtml(nivel.valor)}">
      </label>
      <label class="admin-campo" data-grupo="porcentaje"${esPorc ? '' : ' hidden'}>
        <span>Tope en pesos (opcional)</span>
        <input type="number" min="1" step="1" inputmode="numeric" data-campo="tope" placeholder="Sin tope" value="${escaparHtml(nivel.tope)}">
      </label>
      <label class="admin-campo" data-grupo="producto"${esPorc ? ' hidden' : ''}>
        <span>Producto</span>
        <select data-campo="producto">${opcionesProductoFidelidad(nivel.producto)}</select>
        <small class="admin-ayuda">Se regala la opción más barata, sin costo.</small>
      </label>
      <label class="admin-campo">
        <span>Vence a los (días)</span>
        <input type="number" min="1" max="365" step="1" inputmode="numeric" data-campo="dias" value="${escaparHtml(nivel.dias)}">
      </label>
      <div class="admin-fidelidad-nivel-acciones">
        <button type="button" class="btn-peligro" data-fidelidad-accion="quitar"${total <= 1 ? ' disabled' : ''}>Quitar</button>
      </div>
    </div>`;
  }

  function renderNivelesFidelidad(niveles) {
    if (!el.fidelidadNiveles) return;
    el.fidelidadNiveles.innerHTML = niveles.map((n, i) => htmlNivelFidelidad(n, i, niveles.length)).join('');
  }

  // Lee los niveles tal como están en pantalla (valores crudos).
  function leerNivelesFidelidadDom() {
    if (!el.fidelidadNiveles) return [];
    return Array.from(el.fidelidadNiveles.querySelectorAll('[data-fidelidad-nivel]')).map(fila => {
      const campo = (nombre) => {
        const nodo = fila.querySelector(`[data-campo="${nombre}"]`);
        return nodo ? nodo.value : '';
      };
      return {
        en: campo('en'),
        tipo: campo('tipo'),
        valor: campo('valor'),
        tope: campo('tope'),
        producto: campo('producto'),
        dias: campo('dias')
      };
    });
  }

  function leerFormularioFidelidad() {
    return {
      activo: !!(el.fidelidadActivo && el.fidelidadActivo.checked),
      pedidoMinimo: el.fidelidadPedidoMinimo ? el.fidelidadPedidoMinimo.value : '',
      ciclo: el.fidelidadCiclo ? el.fidelidadCiclo.value : '',
      niveles: leerNivelesFidelidadDom()
    };
  }

  function llenarFormularioFidelidad(datos) {
    if (el.fidelidadActivo) el.fidelidadActivo.checked = datos.activo === true;
    if (el.fidelidadPedidoMinimo) el.fidelidadPedidoMinimo.value = datos.pedidoMinimo;
    if (el.fidelidadCiclo) el.fidelidadCiclo.value = datos.ciclo;
    renderNivelesFidelidad(datos.niveles.length ? datos.niveles : [nivelFidelidadVacio()]);
  }

  function renderEstadisticasFidelidad(premios) {
    if (!el.fidelidadStats) return;
    const ahora = Date.now();
    const etiquetas = { descuento_porcentaje: 'Descuento (%)', producto_gratis: 'Producto gratis' };
    const filas = [];
    const resumir = (nombre, lista) => {
      const usados = lista.filter(p => p.usado).length;
      const vigentes = lista.filter(p => !p.usado && new Date(p.vencimiento).getTime() > ahora).length;
      const vencidos = lista.length - usados - vigentes;
      filas.push(`<div class="admin-cupon-fila">
        <div class="admin-envios-tramo-dato"><small>Tipo</small><span>${escaparHtml(nombre)}</span></div>
        <div class="admin-envios-tramo-dato"><small>Generados</small><span>${escaparHtml(lista.length)}</span></div>
        <div class="admin-envios-tramo-dato"><small>Usados</small><span>${escaparHtml(usados)}</span></div>
        <div class="admin-envios-tramo-dato"><small>Vigentes</small><span>${escaparHtml(vigentes)}</span></div>
        <div class="admin-envios-tramo-dato"><small>Vencidos sin usar</small><span>${escaparHtml(vencidos)}</span></div>
      </div>`);
    };
    Object.keys(etiquetas).forEach(tipo => resumir(etiquetas[tipo], premios.filter(p => p.tipo === tipo)));
    resumir('Total', premios);
    el.fidelidadStats.innerHTML = filas.join('');
  }

  async function cargarEstadisticasFidelidad() {
    if (!el.fidelidadStats) return;
    mostrarEstado(el.fidelidadStatsEstado, 'Cargando estadísticas...');
    el.fidelidadStats.innerHTML = '';
    try {
      const premios = [];
      const PAGINA = 1000;
      for (let desde = 0; desde < 20000; desde += PAGINA) {
        const { data, error } = await cliente
          .from('premios')
          .select('tipo,usado,vencimiento')
          .order('creado_en', { ascending: true })
          .range(desde, desde + PAGINA - 1);
        if (error) throw error;
        const filas = Array.isArray(data) ? data : [];
        premios.push(...filas);
        if (filas.length < PAGINA) break;
      }
      renderEstadisticasFidelidad(premios);
      mostrarEstado(el.fidelidadStatsEstado, '');
    } catch (error) {
      console.warn('No se pudieron cargar las estadísticas de fidelidad:', error);
      mostrarEstado(el.fidelidadStatsEstado, 'No se pudieron cargar las estadísticas', 'error');
    }
  }

  async function cargarFidelidad() {
    if (!cliente || fidelidadCargando || !puedeVerFidelidad()) return;
    fidelidadCargando = true;
    mostrarEstado(el.fidelidadEstado, 'Cargando configuración...');
    mostrarAvisoFidelidad('');
    mostrarEstado(el.fidelidadFormEstado, '');

    try {
      const { data, error } = await cliente
        .from('config_negocio')
        .select('valor')
        .eq('clave', 'fidelidad')
        .maybeSingle();
      if (error) throw error;

      fidelidadConfigGuardada = data ? data.valor : null;
      if (data) {
        const datos = formularioDesdeConfigFidelidad(data.valor);
        llenarFormularioFidelidad(datos);
        if (validarFidelidad(datos).error) {
          mostrarAvisoFidelidad('La configuración actual es inválida: el programa está inactivo.', 'error');
        }
      } else {
        llenarFormularioFidelidad({ activo: false, pedidoMinimo: '0', ciclo: '10', niveles: [nivelFidelidadVacio()] });
        mostrarAvisoFidelidad('Todavía no hay configuración de fidelidad: el programa está inactivo.', 'info');
      }
      fidelidadCargada = true;
      mostrarEstado(el.fidelidadEstado, '');
    } catch (error) {
      console.warn('No se pudo cargar la configuración de fidelidad:', error);
      mostrarEstado(el.fidelidadEstado, '');
      mostrarAvisoFidelidad(esErrorPermiso(error)
        ? 'No tenés permiso para hacer esto.'
        : 'No se pudo cargar la configuración de fidelidad.', 'error');
    } finally {
      fidelidadCargando = false;
    }

    await cargarEstadisticasFidelidad();
  }

  async function guardarFidelidad(evento) {
    if (evento) evento.preventDefault();
    if (!cliente || !puedeVerFidelidad()) return;

    const resultado = validarFidelidad(leerFormularioFidelidad());
    if (resultado.error) {
      mostrarEstado(el.fidelidadFormEstado, resultado.error, 'error');
      return;
    }
    const config = resultado.config;

    const estabaActivo = !!(fidelidadConfigGuardada && fidelidadConfigGuardada.activo === true);
    if (estabaActivo && !config.activo
      && !window.confirm('¿Desactivar el programa de fidelidad? Los clientes dejan de sumar y de ver premios nuevos mientras esté inactivo.')) {
      return;
    }

    if (el.btnGuardarFidelidad) el.btnGuardarFidelidad.disabled = true;
    mostrarEstado(el.fidelidadFormEstado, 'Guardando...');
    try {
      const { error } = await cliente
        .from('config_negocio')
        .upsert({ clave: 'fidelidad', valor: config }, { onConflict: 'clave' });
      if (error) throw error;

      fidelidadConfigGuardada = config;
      llenarFormularioFidelidad(formularioDesdeConfigFidelidad(config));
      mostrarAvisoFidelidad('');
      mostrarEstado(el.fidelidadFormEstado, 'Configuración guardada.', 'ok');
    } catch (error) {
      console.warn('No se pudo guardar la configuración de fidelidad:', error);
      mostrarEstado(el.fidelidadFormEstado, esErrorPermiso(error)
        ? 'No tenés permiso para hacer esto.'
        : 'No se pudo guardar la configuración de fidelidad.', 'error');
    } finally {
      if (el.btnGuardarFidelidad) el.btnGuardarFidelidad.disabled = false;
    }
  }

  function conectarEventosFidelidad() {
    if (el.btnFidelidadRecargar) el.btnFidelidadRecargar.addEventListener('click', () => cargarFidelidad());
    if (el.formFidelidad) el.formFidelidad.addEventListener('submit', guardarFidelidad);
    if (el.btnFidelidadAgregarNivel) {
      el.btnFidelidadAgregarNivel.addEventListener('click', () => {
        const niveles = leerNivelesFidelidadDom();
        if (niveles.length >= FIDELIDAD_MAX_NIVELES) {
          mostrarEstado(el.fidelidadFormEstado, `Pueden ser como máximo ${FIDELIDAD_MAX_NIVELES} niveles.`, 'error');
          return;
        }
        niveles.push(nivelFidelidadVacio());
        renderNivelesFidelidad(niveles);
      });
    }
    if (el.fidelidadNiveles) {
      el.fidelidadNiveles.addEventListener('click', (evento) => {
        const boton = evento.target.closest('[data-fidelidad-accion="quitar"]');
        const fila = boton && boton.closest('[data-fidelidad-nivel]');
        if (!fila) return;
        const filas = Array.from(el.fidelidadNiveles.querySelectorAll('[data-fidelidad-nivel]'));
        if (filas.length <= 1) return;
        const niveles = leerNivelesFidelidadDom();
        niveles.splice(filas.indexOf(fila), 1);
        renderNivelesFidelidad(niveles);
      });
      el.fidelidadNiveles.addEventListener('change', (evento) => {
        const selector = evento.target.closest('[data-campo="tipo"]');
        const fila = selector && selector.closest('[data-fidelidad-nivel]');
        if (!fila) return;
        const esPorc = selector.value !== 'producto_gratis';
        fila.querySelectorAll('[data-grupo="porcentaje"]').forEach(n => { n.hidden = !esPorc; });
        fila.querySelectorAll('[data-grupo="producto"]').forEach(n => { n.hidden = esPorc; });
      });
    }
  }

  // ---------------------------------------------------------------
  // Estadísticas (solo dueño). El servidor calcula todo; acá solo se muestra.
  // ---------------------------------------------------------------
  const estadisticas = { periodo: 'hoy', seq: 0, resumen: null, cupones: null, rango: null, sucursal: null };

  function statsEl(id) { return document.getElementById(id); }

  function fechaArgentinaISO(fecha) {
    return new Intl.DateTimeFormat('en-CA', { timeZone: ZONA_AR, year: 'numeric', month: '2-digit', day: '2-digit' }).format(fecha);
  }

  function sumarDiasISO(iso, dias) {
    const [a, m, d] = iso.split('-').map(Number);
    return new Date(Date.UTC(a, m - 1, d + dias)).toISOString().slice(0, 10);
  }

  // Límites: inicio del día local (-03:00), fin exclusivo.
  function rangoEstadisticas() {
    const hoy = fechaArgentinaISO(new Date());
    let desde = hoy;
    let hasta = hoy;
    if (estadisticas.periodo === '7') desde = sumarDiasISO(hoy, -6);
    else if (estadisticas.periodo === '30') desde = sumarDiasISO(hoy, -29);
    else if (estadisticas.periodo === 'custom') {
      desde = (statsEl('stats-desde') || {}).value || '';
      hasta = (statsEl('stats-hasta') || {}).value || '';
      if (!desde || !hasta) return null;
    }
    return { desde, hasta, p_desde: `${desde}T00:00:00-03:00`, p_hasta: `${sumarDiasISO(hasta, 1)}T00:00:00-03:00` };
  }

  function mensajeErrorStats(error) {
    if (esErrorPermiso(error)) return 'No tenés permiso para hacer esto.';
    const msg = String((error && error.message) || '');
    if (msg.includes('731')) return 'El período no puede superar los 731 días.';
    return 'No se pudieron cargar las estadísticas. Probá de nuevo.';
  }

  function avisoStats(texto) {
    const aviso = statsEl('stats-aviso');
    if (!aviso) return;
    aviso.hidden = !texto;
    aviso.dataset.tipo = 'error';
    aviso.textContent = texto || '';
  }

  async function cargarEstadisticas() {
    if (!cliente || !puedeVerCupones()) return;
    const rango = rangoEstadisticas();
    const contenido = statsEl('stats-contenido');
    const estado = statsEl('stats-estado');
    const btnCsv = statsEl('btn-stats-csv');
    const mi = ++estadisticas.seq; // invalida consultas anteriores
    avisoStats('');
    if (!rango) {
      mostrarEstado(estado, 'Elegí las dos fechas.');
      return;
    }
    if (rango.p_hasta <= rango.p_desde) {
      mostrarEstado(estado, '');
      avisoStats('La fecha "hasta" no puede ser anterior a "desde".');
      return;
    }
    const suc = (statsEl('stats-sucursal') || {}).value || null;
    const args = { p_desde: rango.p_desde, p_hasta: rango.p_hasta, p_sucursal: suc };
    mostrarEstado(estado, 'Cargando estadísticas...');
    if (btnCsv) btnCsv.disabled = true;
    try {
      const [r1, r2] = await Promise.all([
        cliente.rpc('stats_resumen', args),
        cliente.rpc('stats_cupones_fidelidad', args)
      ]);
      if (mi !== estadisticas.seq) return;
      if (r1.error) throw r1.error;
      if (r2.error) throw r2.error;
      estadisticas.resumen = r1.data || {};
      estadisticas.cupones = r2.data || {};
      estadisticas.rango = rango;
      estadisticas.sucursal = suc;
      renderEstadisticas();
      mostrarEstado(estado, '');
      if (contenido) contenido.hidden = false;
      if (btnCsv) btnCsv.disabled = false;
    } catch (error) {
      if (mi !== estadisticas.seq) return;
      console.warn('No se pudieron cargar las estadísticas:', error);
      mostrarEstado(estado, '');
      if (contenido) contenido.hidden = true;
      avisoStats(mensajeErrorStats(error));
    }
  }

  function statsNum(v) { const n = Number(v); return Number.isFinite(n) ? n : 0; }

  function statsVariacion(pct) {
    if (pct === null || pct === undefined || !Number.isFinite(Number(pct))) {
      return '<span class="admin-stats-var">—</span>';
    }
    const n = Number(pct);
    const clase = n > 0 ? 'sube' : (n < 0 ? 'baja' : '');
    const signo = n > 0 ? '▲ +' : (n < 0 ? '▼ ' : '');
    return `<span class="admin-stats-var ${clase}">${signo}${PM.escaparHtml(String(n).replace('.', ','))}%</span>`;
  }

  function statsTarjeta(titulo, valor, variacion) {
    return `<div class="admin-stats-tarjeta"><span class="admin-stats-tit">${PM.escaparHtml(titulo)}</span>`
      + `<strong>${PM.escaparHtml(valor)}</strong>`
      + `<span class="admin-stats-sub">${variacion === undefined ? '&nbsp;' : statsVariacion(variacion) + ' vs. período anterior'}</span></div>`;
  }

  function statsLista(filas, vacio) {
    if (!filas.length) return `<p class="admin-envios-vacio">${PM.escaparHtml(vacio)}</p>`;
    const max = Math.max(...filas.map(f => f.valor), 1);
    return '<ul class="admin-stats-lista">' + filas.map(f => `<li class="admin-stats-lista-fila">
      <span class="admin-stats-lista-nombre" title="${PM.escaparHtml(f.nombre)}">${PM.escaparHtml(f.nombre)}</span>
      <span class="admin-stats-barra"><i style="width:${Math.max(2, Math.round(f.valor / max * 100))}%"></i></span>
      <span class="admin-stats-lista-cant">${PM.escaparHtml(f.cant)}</span>
      <span class="admin-stats-lista-total">${PM.escaparHtml(f.total)}</span></li>`).join('') + '</ul>';
  }

  // Barras SVG: datos = [{etiqueta, valor, titulo}]; el titulo es el tooltip.
  function statsBarrasSvg(datos, opciones = {}) {
    if (!datos.length) return '<p class="admin-envios-vacio">Sin datos en el período.</p>';
    const W = 640, H = 220, izq = 50, der = 8, arr = 10, aba = 28;
    const max = Math.max(...datos.map(d => d.valor), 0);
    const tope = max > 0 ? max : 1;
    const ancho = (W - izq - der) / datos.length;
    const barra = Math.max(2, ancho * 0.7);
    const alto = H - arr - aba;
    const ejeY = [0, 0.5, 1].map(f => {
      const y = arr + alto - alto * f;
      const txt = opciones.formatoEje ? opciones.formatoEje(tope * f) : String(Math.round(tope * f));
      return `<line x1="${izq}" x2="${W - der}" y1="${y}" y2="${y}" class="adm-eje"/><text x="${izq - 6}" y="${y + 4}" text-anchor="end" class="adm-txt">${PM.escaparHtml(txt)}</text>`;
    }).join('');
    const salto = Math.ceil(datos.length / (opciones.maxEtiquetas || 8));
    const barras = datos.map((d, i) => {
      const h = d.valor / tope * alto;
      const x = izq + i * ancho + (ancho - barra) / 2;
      const y = arr + alto - h;
      const et = i % salto === 0 ? `<text x="${x + barra / 2}" y="${H - 10}" text-anchor="middle" class="adm-txt">${PM.escaparHtml(d.etiqueta)}</text>` : '';
      return `<g class="adm-barra" tabindex="0"><title>${PM.escaparHtml(d.titulo)}</title><rect x="${x}" y="${arr}" width="${barra}" height="${alto}" fill="transparent"/><rect class="adm-r" x="${x}" y="${y}" width="${barra}" height="${Math.max(h, d.valor > 0 ? 1 : 0)}" rx="2"/></g>${et}`;
    }).join('');
    return `<svg viewBox="0 0 ${W} ${H}" class="admin-stats-svg" role="img" aria-label="${PM.escaparHtml(opciones.alt || 'Gráfico de barras')}">${ejeY}${barras}</svg>`;
  }

  function statsPlata(v) { return formatearPrecio(statsNum(v)); }

  function statsCompacto(v) {
    const n = statsNum(v);
    if (n >= 1000000) return `$${(n / 1000000).toFixed(1).replace('.', ',')} M`;
    if (n >= 1000) return `$${Math.round(n / 1000)} mil`;
    return `$${Math.round(n)}`;
  }

  function renderEstadisticas() {
    const r = estadisticas.resumen || {};
    const c = estadisticas.cupones || {};
    const v = r.variacion || {};
    const pon = (id, html) => { const nodo = statsEl(id); if (nodo) nodo.innerHTML = html; };

    pon('stats-tarjetas',
      statsTarjeta('Facturación', statsPlata(r.facturacion), v.facturacion_pct)
      + statsTarjeta('Pedidos entregados', String(statsNum(r.pedidos)), v.pedidos_pct)
      + statsTarjeta('Ticket promedio', statsPlata(r.ticket_promedio), v.ticket_pct)
      + statsTarjeta('Cancelados', String(statsNum(r.cancelados)))
      + statsTarjeta('Envío cobrado', statsPlata(r.envio_cobrado))
      + statsTarjeta('Regalos', String(statsNum(r.regalos))));

    const dias = (Array.isArray(r.ventas_por_dia) ? r.ventas_por_dia : []).map(d => {
      const f = String(d.dia || '');
      const corta = f.length >= 10 ? `${f.slice(8, 10)}/${f.slice(5, 7)}` : f;
      return { etiqueta: corta, valor: statsNum(d.facturacion), titulo: `${corta}: ${statsPlata(d.facturacion)} · ${statsNum(d.pedidos)} pedidos` };
    });
    pon('stats-dias', statsBarrasSvg(dias, { formatoEje: statsCompacto, alt: 'Ventas por día' }));

    const porHora = new Map((Array.isArray(r.ventas_por_hora) ? r.ventas_por_hora : []).map(h => [Number(h.hora), h]));
    const horas = Array.from({ length: 24 }, (_, h) => {
      const x = porHora.get(h) || {};
      return { etiqueta: String(h), valor: statsNum(x.pedidos), titulo: `${h}:00 hs: ${statsNum(x.pedidos)} pedidos · ${statsPlata(x.facturacion)}` };
    });
    pon('stats-horas', statsBarrasSvg(horas, { maxEtiquetas: 12, alt: 'Pedidos por hora' }));

    pon('stats-pagos', statsLista((r.metodos_pago || []).map(m => ({
      nombre: m.metodo || 'Sin dato', valor: statsNum(m.facturacion),
      cant: `${statsNum(m.pedidos)} ped.`, total: statsPlata(m.facturacion)
    })), 'Sin datos en el período.'));
    pon('stats-modalidades', statsLista((r.modalidades || []).map(m => ({
      nombre: etiquetaModalidadPedido(m.modalidad), valor: statsNum(m.pedidos),
      cant: `${statsNum(m.pedidos)} ped.`, total: statsPlata(m.facturacion)
    })), 'Sin datos en el período.'));
    pon('stats-top', statsLista((r.top_productos || []).map(p => ({
      nombre: p.nombre || p.producto_id || 'Producto', valor: statsNum(p.cantidad),
      cant: `${statsNum(p.cantidad)} u.`, total: statsPlata(p.ingresos)
    })), 'Sin ventas en el período.'));

    const cupones = Array.isArray(c.cupones) ? c.cupones : [];
    pon('stats-cupones', cupones.length
      ? '<div class="admin-stats-tabla-wrap"><table class="admin-stats-tabla"><thead><tr><th>Cupón</th><th>Usos</th><th>Ventas</th><th>Descuento</th></tr></thead><tbody>'
        + cupones.map(x => `<tr><td>${PM.escaparHtml(x.codigo)}</td><td>${statsNum(x.usos)}</td><td>${PM.escaparHtml(statsPlata(x.ventas_generadas))}</td><td>${PM.escaparHtml(statsPlata(x.descuento_otorgado))}</td></tr>`).join('')
        + '</tbody></table></div>'
      : '<p class="admin-envios-vacio">No se usaron cupones en el período.</p>');

    const f = c.fidelidad || {};
    const costo = f.regalos_costo_estimado === null || f.regalos_costo_estimado === undefined ? 'sin dato' : statsPlata(f.regalos_costo_estimado);
    pon('stats-fidelidad', '<dl class="admin-stats-dl">'
      + `<div><dt>Premios generados</dt><dd>${statsNum(f.premios_generados)}</dd></div>`
      + `<div><dt>Canjeados</dt><dd>${statsNum(f.premios_canjeados)}</dd></div>`
      + `<div><dt>Descuento por premios</dt><dd>${PM.escaparHtml(statsPlata(f.descuento_premios_porcentaje))}</dd></div>`
      + `<div><dt>Regalos</dt><dd>${statsNum(f.regalos)}</dd></div>`
      + `<div><dt>Costo de regalos</dt><dd>${PM.escaparHtml(costo)}</dd></div></dl>`);
  }

  function exportarEstadisticasCsv() {
    const r = estadisticas.resumen;
    if (!r || !estadisticas.rango) return;
    const filas = [
      ['Periodo', `${estadisticas.rango.desde} a ${estadisticas.rango.hasta}`],
      ['Sucursal', estadisticas.sucursal ? (SUCURSALES_CORTO[estadisticas.sucursal] || estadisticas.sucursal) : 'Todas'],
      ['Facturacion', r.facturacion], ['Pedidos entregados', r.pedidos], ['Ticket promedio', r.ticket_promedio],
      ['Cancelados', r.cancelados], ['Envio cobrado', r.envio_cobrado], ['Regalos', r.regalos],
      [], ['Top productos'], ['Producto', 'Cantidad', 'Ingresos'],
      ...(r.top_productos || []).map(p => [p.nombre || p.producto_id, p.cantidad, p.ingresos])
    ];
    const contenido = '﻿' + filas.map(fila => fila.map(campoCsv).join(';')).join('\r\n');
    const blob = new Blob([contenido], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `estadisticas-${estadisticas.rango.desde}-a-${estadisticas.rango.hasta}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function conectarEventosEstadisticas() {
    document.querySelectorAll('[data-stats-periodo]').forEach(boton => {
      boton.addEventListener('click', () => {
        estadisticas.periodo = boton.dataset.statsPeriodo;
        document.querySelectorAll('[data-stats-periodo]').forEach(b => b.classList.toggle('activa', b === boton));
        const rango = statsEl('stats-rango');
        if (rango) rango.hidden = estadisticas.periodo !== 'custom';
        if (estadisticas.periodo === 'custom') {
          const hoy = fechaArgentinaISO(new Date());
          const d = statsEl('stats-desde');
          const h = statsEl('stats-hasta');
          if (d && !d.value) d.value = sumarDiasISO(hoy, -6);
          if (h && !h.value) h.value = hoy;
        }
        cargarEstadisticas();
      });
    });
    ['stats-sucursal', 'stats-desde', 'stats-hasta'].forEach(id => {
      const nodo = statsEl(id);
      if (nodo) nodo.addEventListener('change', cargarEstadisticas);
    });
    const rec = statsEl('btn-stats-recargar');
    if (rec) rec.addEventListener('click', cargarEstadisticas);
    const csv = statsEl('btn-stats-csv');
    if (csv) csv.addEventListener('click', exportarEstadisticasCsv);
  }

  function mostrarVistaAdmin(vista) {
    if (vista === 'cupones' && !puedeVerCupones()) vista = 'pedidos';
    if (vista === 'fidelidad' && !puedeVerFidelidad()) vista = 'pedidos';
    if (vista === 'estadisticas' && !puedeVerCupones()) vista = 'pedidos';
    const esStats = vista === 'estadisticas';
    const vistaStats = document.getElementById('admin-vista-estadisticas');
    if (vistaStats) vistaStats.hidden = !esStats;
    if (esStats && cliente) cargarEstadisticas();
    const esPedidos = vista === 'pedidos';
    const esEnvios = vista === 'envios';
    const esCupones = vista === 'cupones';
    const esFidelidad = vista === 'fidelidad';
    el.tabsVista.forEach(tab => {
      const activa = tab.dataset.adminVista === vista;
      tab.classList.toggle('activa', activa);
      tab.setAttribute('aria-selected', activa ? 'true' : 'false');
    });
    if (el.vistaCarta) el.vistaCarta.hidden = esPedidos || esEnvios || esCupones || esFidelidad || esStats;
    if (el.vistaFidelidad) el.vistaFidelidad.hidden = !esFidelidad;
    if (esFidelidad && cliente) {
      if (!fidelidadCargada) cargarFidelidad();
      else cargarEstadisticasFidelidad();
    }
    if (el.vistaCupones) el.vistaCupones.hidden = !esCupones;
    if (esCupones && cliente) {
      if (!cuponesCargados) cargarCupones();
      else renderCupones();
    }
    if (el.vistaPedidos) el.vistaPedidos.hidden = !esPedidos;
    if (el.vistaEnvios) el.vistaEnvios.hidden = !esEnvios;
    if (esPedidos && cliente) {
      if (!pedidosCargados) cargarPedidos();
      else renderPedidos();
      if (!agotadosCargados) cargarAgotados();
      else renderAgotados();
    }
    if (esEnvios && cliente) {
      if (!enviosCargados) cargarEnvios();
      else {
        renderConfigEnvios();
        renderZonasNormales();
        renderTramosEnvios();
      }
    }
    if (adminRolError) aplicarAvisoRol();
  }

  function conectarEventos() {
    if (el.formLogin) el.formLogin.addEventListener('submit', iniciarSesion);
    if (el.btnLogout) el.btnLogout.addEventListener('click', cerrarSesion);
    if (el.btnGuardar) el.btnGuardar.addEventListener('click', guardarCarta);
    if (el.btnExportar) el.btnExportar.addEventListener('click', exportarCarta);
    if (el.btnRecargar) {
      el.btnRecargar.addEventListener('click', async () => {
        if (cambiosPendientes && !window.confirm('Hay cambios sin guardar. ¿Recargar de todos modos?')) return;
        await cargarCarta();
      });
    }

    el.tabsVista.forEach(tab => {
      tab.addEventListener('click', () => mostrarVistaAdmin(tab.dataset.adminVista));
    });

    if (el.btnPedidosActualizar) {
      el.btnPedidosActualizar.addEventListener('click', () => cargarPedidos());
    }
    if (el.btnPedidosActivarSonido) {
      el.btnPedidosActivarSonido.addEventListener('click', alternarSonidoPedidos);
    }
    if (el.pedidosVolumen) {
      el.pedidosVolumen.addEventListener('change', cambiarVolumenPedidos);
    }
    document.addEventListener('pointerdown', () => {
      if (!pedidosSonidoActivo) return;
      desbloquearAudioPedidos();
    }, { capture: true, once: true });
    if (el.pedidosFiltroPeriodo) {
      el.pedidosFiltroPeriodo.addEventListener('change', () => {
        cambiarPeriodoPedidos(el.pedidosFiltroPeriodo.value);
      });
    }
    if (el.pedidosPeriodoEtiqueta) {
      el.pedidosPeriodoEtiqueta.addEventListener('click', volverAHoyPedidos);
    }
    if (el.btnPedidosAnterior) {
      el.btnPedidosAnterior.addEventListener('click', () => moverPeriodoPedidos(-1));
    }
    if (el.btnPedidosSiguiente) {
      el.btnPedidosSiguiente.addEventListener('click', () => moverPeriodoPedidos(1));
    }
    if (el.pedidosFiltroDesde) {
      el.pedidosFiltroDesde.addEventListener('change', () => aplicarCambioRangoPedidos('desde'));
    }
    if (el.pedidosFiltroHasta) {
      el.pedidosFiltroHasta.addEventListener('change', () => aplicarCambioRangoPedidos('hasta'));
    }
    if (el.pedidosFiltroSucursal) el.pedidosFiltroSucursal.addEventListener('change', renderPedidos);
    el.pedidosVistaBtns.forEach(boton => {
      boton.addEventListener('click', () => {
        pedidosVista = boton.dataset.pedidosVista === 'lista' ? 'lista' : 'tablero';
        actualizarControlesPedidos();
        renderPedidos();
      });
    });
    el.pedidosModalidadBtns.forEach(boton => {
      boton.addEventListener('click', () => {
        pedidosModalidad = boton.dataset.pedidosModalidad || '';
        actualizarControlesPedidos();
        renderPedidos();
      });
    });
    if (el.btnPedidosExportar) el.btnPedidosExportar.addEventListener('click', exportarPedidosCsv);
    if (el.agotadosSucursal) {
      el.agotadosSucursal.addEventListener('change', () => renderAgotados());
    }
    if (el.agotadosLista) {
      el.agotadosLista.addEventListener('click', (evento) => {
        if (evento.target.closest('[data-agotados-ver-todos]')) {
          agotadosFiltroEstado = 'todos';
          renderAgotados();
          return;
        }
        const boton = evento.target.closest('[data-agotado-id]');
        if (!boton || boton.disabled) return;
        cambiarAgotado(boton.dataset.agotadoId, boton.dataset.agotadoSucursal, boton.getAttribute('aria-checked') !== 'true', { origen: 'pedidos' });
      });
    }
    if (el.agotadosBuscar) el.agotadosBuscar.addEventListener('input', renderAgotados);
    if (el.agotadosCategoria) el.agotadosCategoria.addEventListener('change', renderAgotados);
    if (el.agotadosFiltroEstado) {
      el.agotadosFiltroEstado.addEventListener('change', () => {
        agotadosFiltroEstado = el.agotadosFiltroEstado.value || 'no-disponibles';
        renderAgotados();
      });
    }

    if (el.pedidosContenedor) {
      el.pedidosContenedor.addEventListener('click', async (evento) => {
        const botonColumna = evento.target.closest('[data-columna-toggle]');
        const columnaCerrada = botonColumna ? null : evento.target.closest('.admin-pedidos-columna.colapsada');
        if (botonColumna || columnaCerrada) {
          const columna = (botonColumna || columnaCerrada).closest('[data-columna]');
          if (columna) {
            const colapsada = !columna.classList.contains('colapsada');
            aplicarEstadoColumnaCancelados(columna, colapsada);
            guardarCanceladosAbierto(!colapsada);
            if (!colapsada) {
              // en celular el carril es horizontal: dejar la columna a la vista
              const reducir = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
              if (window.matchMedia && window.matchMedia('(max-width: 720px)').matches) {
                columna.scrollIntoView({ behavior: reducir ? 'auto' : 'smooth', inline: 'end', block: 'nearest' });
              }
              const foco = columna.querySelector('[data-columna-toggle]');
              if (foco && botonColumna) foco.focus();
            } else {
              const foco = columna.querySelector('[data-columna-toggle]');
              if (foco && botonColumna) foco.focus();
            }
          }
          return;
        }

        const boton = evento.target.closest('[data-pedido-accion]');
        if (boton) {
          const tarjeta = boton.closest('[data-pedido-id]');
          if (tarjeta) await ejecutarAccionPedido(tarjeta.dataset.pedidoId, boton.dataset.pedidoAccion, boton);
          return;
        }

        if (evento.target.closest('summary, details, a, input, select, textarea, label')) return;
        const tarjeta = evento.target.closest('[data-pedido-id]');
        if (tarjeta) abrirDetallePedido(tarjeta.dataset.pedidoId);
      });
    }

    if (el.pedidoDetalleContenido) {
      el.pedidoDetalleContenido.addEventListener('click', async (evento) => {
        const boton = evento.target.closest('[data-pedido-accion]');
        if (!boton || !pedidoAbiertoId) return;
        await ejecutarAccionPedido(pedidoAbiertoId, boton.dataset.pedidoAccion, boton);
      });
    }

    if (el.btnCerrarModalPedido) el.btnCerrarModalPedido.addEventListener('click', cerrarModalPedido);
    if (el.modalPedido) {
      el.modalPedido.addEventListener('click', (evento) => {
        if (evento.target === el.modalPedido) cerrarModalPedido();
      });
    }

    if (el.btnEnviosRecargar) {
      el.btnEnviosRecargar.addEventListener('click', () => cargarEnvios());
    }
    if (el.formConfigEnvios) el.formConfigEnvios.addEventListener('submit', guardarConfigEnvios);
    if (el.btnNuevoTramo) el.btnNuevoTramo.addEventListener('click', () => abrirFormTramo(null));
    conectarEventosFidelidad();
    conectarEventosEstadisticas();
    if (el.btnNuevoCupon) el.btnNuevoCupon.addEventListener('click', () => abrirFormCupon(null));
    if (el.btnCuponesRecargar) el.btnCuponesRecargar.addEventListener('click', () => cargarCupones());
    [el.btnCancelarCupon, el.btnCancelarCuponArriba, el.btnCerrarCupon].forEach(boton => {
      if (boton) boton.addEventListener('click', cerrarFormCupon);
    });
    if (el.formCupon) el.formCupon.addEventListener('submit', guardarCupon);
    if (el.cuponTipo) el.cuponTipo.addEventListener('change', actualizarEtiquetaValorCupon);
    if (el.cuponesLista) {
      el.cuponesLista.addEventListener('click', async (evento) => {
        const boton = evento.target.closest('[data-cupon-accion]');
        const fila = boton && boton.closest('[data-cupon-id]');
        if (!fila) return;
        const id = fila.dataset.cuponId;
        const accion = boton.dataset.cuponAccion;
        if (accion === 'editar') {
          const cupon = cuponesLista.find(item => String(item.id) === String(id));
          if (cupon) abrirFormCupon(cupon);
        } else if (accion === 'toggle') {
          await alternarCupon(id);
        } else if (accion === 'eliminar') {
          await borrarCupon(id);
        }
      });
    }
    if (el.btnCancelarTramo) el.btnCancelarTramo.addEventListener('click', cerrarFormTramo);
    if (el.formTramo) el.formTramo.addEventListener('submit', guardarTramo);

    if (el.tramosLista) {
      el.tramosLista.addEventListener('click', async (evento) => {
        const boton = evento.target.closest('[data-tramo-accion]');
        if (!boton) return;
        const contenedor = boton.closest('[data-tramo-id]');
        if (!contenedor) return;
        const id = contenedor.dataset.tramoId;
        const accion = boton.dataset.tramoAccion;
        if (accion === 'editar') {
          const tramo = tramosEnvios.find(item => String(item.id) === String(id));
          if (tramo) abrirFormTramo(tramo);
        } else if (accion === 'toggle') {
          await toggleTramo(id);
        } else if (accion === 'eliminar') {
          await eliminarTramo(id);
        }
      });
    }

    if (el.zonasNormalesLista) {
      el.zonasNormalesLista.addEventListener('click', async (evento) => {
        const boton = evento.target.closest('[data-zona-guardar]');
        if (!boton) return;
        const contenedor = boton.closest('[data-zona-id]');
        if (contenedor) await guardarZonaNormal(contenedor.dataset.zonaId);
      });
    }

    if (el.btnNuevaCategoria) el.btnNuevaCategoria.addEventListener('click', () => abrirModalCategoria('crear'));
    if (el.btnEditarCategoria) {
      el.btnEditarCategoria.addEventListener('click', () => {
        if (categoriaActivaId) abrirModalCategoria('editar', categoriaActivaId);
      });
    }
    if (el.btnNuevoProducto) el.btnNuevoProducto.addEventListener('click', abrirFormularioProducto);
    if (el.btnVacioNuevoProducto) el.btnVacioNuevoProducto.addEventListener('click', abrirFormularioProducto);
    if (el.btnCerrarFormProducto) el.btnCerrarFormProducto.addEventListener('click', cerrarFormularioProducto);
    if (el.btnCancelarProducto) el.btnCancelarProducto.addEventListener('click', cerrarFormularioProducto);
    if (el.formProducto) el.formProducto.addEventListener('submit', agregarProducto);
    if (el.productoTipoOferta) {
      el.productoTipoOferta.addEventListener('change', () => {
        const esFecha = el.productoTipoOferta.value === 'fecha';
        if (el.productoOfertaFechaCampo) el.productoOfertaFechaCampo.hidden = !esFecha;
        if (!esFecha && el.productoOfertaHasta) el.productoOfertaHasta.value = '';
      });
    }

    if (el.btnSubirProducto) {
      el.btnSubirProducto.addEventListener('click', () => abrirSelectorArchivo(el.productoFotoFile));
    }
    conectarZonaArchivo(el.productoFotoZona, el.productoFotoFile);
    if (el.productoFotoFile) {
      el.productoFotoFile.addEventListener('change', () => {
        const archivo = el.productoFotoFile.files[0];
        el.productoFotoFile.value = '';
        if (archivo) subirImagenNueva(archivo);
      });
    }

    if (el.btnCerrarModalCategoria) el.btnCerrarModalCategoria.addEventListener('click', cerrarModalCategoria);
    if (el.btnCancelarCategoria) el.btnCancelarCategoria.addEventListener('click', cerrarModalCategoria);
    if (el.modalCategoria) {
      el.modalCategoria.addEventListener('click', (evento) => {
        if (evento.target === el.modalCategoria) cerrarModalCategoria();
      });
    }
    if (el.formCategoria) el.formCategoria.addEventListener('submit', guardarCategoria);
    if (el.btnSubirCategoria) {
      el.btnSubirCategoria.addEventListener('click', () => abrirSelectorArchivo(el.categoriaFotoFile));
    }
    conectarZonaArchivo(el.categoriaFotoZona, el.categoriaFotoFile);
    if (el.categoriaFotoFile) {
      el.categoriaFotoFile.addEventListener('change', () => {
        const archivo = el.categoriaFotoFile.files[0];
        el.categoriaFotoFile.value = '';
        if (archivo) subirImagenCategoria(archivo);
      });
    }

    if (el.listaCategorias) {
      el.listaCategorias.addEventListener('click', (evento) => {
        const boton = evento.target.closest('[data-accion]');
        if (!boton) return;
        const id = boton.dataset.id;
        if (boton.dataset.accion === 'editar-categoria') abrirModalCategoria('editar', id);
        else if (boton.dataset.accion === 'seleccionar-categoria') seleccionarCategoria(id, true);
      });

      el.listaCategorias.addEventListener('error', (evento) => {
        const imagen = evento.target;
        if (!imagen || !imagen.classList || !imagen.classList.contains('admin-cat-foto')) return;
        if (imagen.dataset.fallback === '1') return;
        imagen.dataset.fallback = '1';
        imagen.src = 'assets/logo.webp';
      }, true);
    }

    if (el.listaProductos) {
      el.listaProductos.addEventListener('input', (evento) => {
        const control = evento.target.closest('[data-campo-producto]');
        if (control && control.tagName !== 'SELECT') actualizarCampoProducto(control);
      });

      el.listaProductos.addEventListener('change', (evento) => {
        const archivo = evento.target.closest('[data-file-producto]');
        if (archivo) {
          const card = archivo.closest('[data-id]');
          const seleccionado = archivo.files[0];
          archivo.value = '';
          if (card && seleccionado) subirImagenProducto(card.dataset.id, seleccionado);
          return;
        }

        const control = evento.target.closest('[data-campo-producto]');
        if (control && control.tagName === 'SELECT') actualizarCampoProducto(control);
      });

      el.listaProductos.addEventListener('click', (evento) => {
        const sw = evento.target.closest('[data-agotado-carta]');
        if (sw) {
          if (!sw.disabled) {
            cambiarAgotado(sw.dataset.agotadoCarta, sw.dataset.agotadoSucursal, sw.getAttribute('aria-checked') !== 'true', { origen: 'carta' });
          }
          return;
        }
        const zona = evento.target.closest('[data-upload-zona]');
        const boton = evento.target.closest('[data-accion]');

        if (boton) {
          const id = boton.dataset.id;
          const accion = boton.dataset.accion;

          if (accion === 'toggle-producto') toggleProducto(id);
          else if (accion === 'eliminar-producto') eliminarProducto(id);
          else if (accion === 'subir-imagen-producto') {
            const archivo = zona ? zona.querySelector('[data-file-producto]') : null;
            abrirSelectorArchivo(archivo);
          }
          return;
        }

        if (!zona || evento.target.closest('button, input, a, label, select, textarea')) return;
        abrirSelectorArchivo(zona.querySelector('[data-file-producto]'));
      });

      el.listaProductos.addEventListener('error', (evento) => {
        const imagen = evento.target;
        if (!imagen || !imagen.classList) return;
        if (!imagen.classList.contains('admin-prod-thumb') && !imagen.classList.contains('admin-upload-preview')) return;
        if (imagen.dataset.fallback === '1') return;
        imagen.dataset.fallback = '1';
        imagen.src = 'assets/logo.webp';
      }, true);
    }

    if (el.detalleFoto) {
      el.detalleFoto.addEventListener('error', () => {
        if (el.detalleFoto.dataset.fallback === '1') return;
        el.detalleFoto.dataset.fallback = '1';
        el.detalleFoto.src = 'assets/logo.webp';
      });
    }

    if (el.productoFotoPreview) {
      el.productoFotoPreview.addEventListener('error', () => {
        if (el.productoFotoPreview.dataset.fallback === '1') return;
        el.productoFotoPreview.dataset.fallback = '1';
        el.productoFotoPreview.src = 'assets/logo.webp';
      });
    }

    if (el.categoriaFotoPreview) {
      el.categoriaFotoPreview.addEventListener('error', () => {
        if (el.categoriaFotoPreview.dataset.fallback === '1') return;
        el.categoriaFotoPreview.dataset.fallback = '1';
        el.categoriaFotoPreview.src = 'assets/logo.webp';
      });
    }

    document.addEventListener('keydown', (evento) => {
      if (evento.key !== 'Escape') return;
      if (el.formCupon && !el.formCupon.hidden && el.formCupon.contains(document.activeElement)) {
        cerrarFormCupon();
        return;
      }
      if (el.modalCategoria && !el.modalCategoria.hidden) {
        cerrarModalCategoria();
        return;
      }
      if (el.modalPedido && !el.modalPedido.hidden) {
        cerrarModalPedido();
        return;
      }
      if (el.panelNuevoProducto && !el.panelNuevoProducto.hidden) cerrarFormularioProducto();
    });

    window.addEventListener('beforeunload', (evento) => {
      if (!cambiosPendientes) return;
      evento.preventDefault();
      evento.returnValue = '';
    });
  }

  async function iniciar() {
    cargarPreferenciasSonido();
    actualizarEstadoSonido();
    inicializarFiltrosPedidos();
    conectarEventos();
    await Promise.all([cargarConfig(), cargarSucursalesConfig()]);

    const configOk = configValida();
    if (el.configPendiente) {
      el.configPendiente.hidden = configOk;
      el.configPendiente.open = !configOk;
    }

    if (el.emailWrap) el.emailWrap.hidden = false;
    if (el.emailInput) el.emailInput.required = true;

    if (!configOk) {
      mostrarEstado(el.loginEstado, 'Falta configurar data/nube.json para conectar la base de datos.', 'error');
      el.btnLogin.disabled = true;
      return;
    }

    if (!inicializarCliente()) {
      if (el.configPendiente) el.configPendiente.hidden = false;
      mostrarEstado(el.loginEstado, 'No se pudo cargar el cliente de Supabase. Revisá la conexión.', 'error');
      el.btnLogin.disabled = true;
      return;
    }

    // Configurar el observador de sesión una única vez de forma global
    cliente.auth.onAuthStateChange((evento, sesion) => {
      if (sesion && sesion.user) {
        if (el.panel && el.panel.hidden) mostrarPanel(sesion.user);
      } else {
        mostrarLogin();
      }
    });

    try {
      const { data } = await cliente.auth.getSession();
      if (data && data.session && data.session.user) {
        await mostrarPanel(data.session.user);
      } else {
        mostrarLogin();
      }
    } catch (error) {
      mostrarLogin();
      mostrarEstado(el.loginEstado, 'No se pudo comprobar la sesión: ' + (error.message || 'error de conexión'), 'error');
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();