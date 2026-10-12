// lib/features/products/presentation/pages/product_form_dialog.dart

// Legacy entry point. The full-screen form lives in
// `product_form_page.dart`. Re-exporting here keeps every existing
// import site (`products_page.dart`, `pos_payment_dialog.dart`, …)
// working without modification.

export 'product_form_page.dart'
    show ProductFormPage, showProductFormDialog;
