(defun read-gif (path)
  (let ((arr (make-array 0 :fill-pointer 0 :element-type '(unsigned-byte 8))))
    (with-open-file (s path :direction :input :element-type '(unsigned-byte 8))
      (loop :do (let ((c (read-byte s nil :eof)))
                  (if (eql c :eof)
                      (return)
                      (vector-push-extend c arr)))))
    arr))

(defun write-gif (path gif)
  (with-open-file (s path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
    (loop :for c :across gif :do (write-byte c s))))

(defun parse-gif (gif)
  (flet ((read-unsigned-2-le (arr idx)
           (+ (aref arr idx) (ash (aref arr (1+ idx)) 8)))
         (make-unsigned-2-le (val)
           (values (logand val #xff) (logand #xff (ash val -8)))))
    (macrolet ((skip-color-table (packed-fields)
                 `(let ((color-table-size (1+ (logand ,packed-fields #b111)))
                        (color-table-present (not (= (ash ,packed-fields -7) 0))))
                    (when color-table-present
                      (setq idx (+ idx (* (ash 1 color-table-size) 3)))))))
      (unless (or (equalp (subseq gif 0 6) #(71 73 70 56 57 97)) ;; GIF89a
                  (equalp (subseq gif 0 6) #(71 30 70 56 55 97))) ;;; GIF87a
        (error "not a GIF"))
      (let ((idx 13))
        (skip-color-table (aref gif 10))
        (loop (ecase (aref gif idx)
                (#x21 ;;; Extension
                 (let ((block-length (+ 3 (aref gif (+ 2 idx)))))
                   (ecase (aref gif (1+ idx))
                     (#xf9 ;;; Graphics Control Extension
                      (let ((delay (max 2 (ceiling (/ (read-unsigned-2-le gif (+ idx 4)) 2)))))
                        (multiple-value-bind (b1 b2) (make-unsigned-2-le delay)
                          (setf (aref gif (+ idx 4)) b1)
                          (setf (aref gif (+ idx 5)) b2)))
                      (setq idx (+ idx block-length)))
                     (#xff ;;; App Extension Block
                      (setq idx (+ idx block-length (aref gif (+ idx block-length))))
                      ;;; XXX XMP Data doesn't actually use sub-block size?
                      (loop (if (eql (aref gif idx) 0) 
                                (progn (incf idx) (return))
                                (incf idx))))
                     (#xfe ;;; Comment Extension
                      (loop (if (eql (aref gif idx) 0)
                                (return)
                                (incf idx))))))
                 (incf idx))
                (#x2c ;;; Image descriptor
                 (skip-color-table (aref gif (+ idx 9)))
                 (setq idx (+ idx 11))
                 (loop (let ((inc (aref gif idx)))
                         (if (= inc 0)
                             (progn (incf idx)
                                    (return))
                             (setq idx (+ idx inc 1))))))
                (#x3b ;;; Trailer
                 (return))))))))

(defun speedup-gif (in-path out-path)
  (let ((gif (read-gif in-path)))
    (parse-gif gif)
    (write-gif out-path gif)))

(defun main ()
  (when (< (length sb-ext:*posix-argv*) 3)
    (format *error-output* "Usage: ~a <in-path> <out-path>~%" (car sb-ext:*posix-argv*))
    (sb-ext:exit :code 1))
  (handler-case
      (speedup-gif (cadr sb-ext:*posix-argv*) (caddr sb-ext:*posix-argv*))
    (t (c)
      (prog2 (format *error-output* "Error: ~a~%" c)
        (sb-ext:exit :code 1)))))
