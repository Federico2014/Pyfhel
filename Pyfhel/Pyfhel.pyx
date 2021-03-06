# distutils: language = c++
#cython: language_level=3, boundscheck=False

#   --------------------------------------------------------------------
#   Pyfhel.pyx
#   Author: Alberto Ibarrondo
#   Date: 17/07/2018
#   --------------------------------------------------------------------
#   License: GNU GPL v3
#
#   Pyfhel is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   Pyfhel is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#   --------------------------------------------------------------------
"""PYFHEL, PYthon For Homomorphic Encryption Libraries.

Encrypted addition, multiplication, substraction, exponentiation of 
integers/doubles. Implementation of homomorphic encryption using 
SEAL/PALISADE/HELIB as backend. Pyfhel works with PyPtxt as  
plaintext class and PyCtxt as cyphertext class.

Example:
    >>> he = Pyfhel()
    >>> he.ContextGen(p=65537)
    >>> he.KeyGen(p=65537)
    >>> p1 = he.encode(4)
    >>> p2 = he.encode(2)
    >>> c1 = he.encrypt(p1)
    >>> c2 = he.encrypt(p2)
    >>> c1 = c1 + c2
    >>> p_res = he.decrypt(c1)
    6
"""    

# -------------------------------- IMPORTS ------------------------------------
# Both numpy and the Cython declarations for numpy
import numpy as np
np.import_array()

# Type checking for only numeric values
from numbers import Number

# Dereferencing pointers in Cython in a secure way
from cython.operator cimport dereference as deref

# Encoding types: 1-UNDEFINED, 2-INTEGER, 3-FRACTIONAL, 4-BATCH
from .util import ENCODING_t

# Define Plaintext types
FLOAT_T = (float, np.float16, np.float32, np.float64)
VALUE_T = FLOAT_T + (int, np.ndarray)

# ------------------------- PYTHON IMPLEMENTATION -----------------------------
cdef class Pyfhel:
    """PYFHEL, PYthon For Homomorphic Encryption Libraries.

    Encrypted addition, multiplication, substraction, exponentiation of 
    integers/doubles. Implementation of homomorphic encryption using 
    SEAL/PALISADE/HELIB as backend. Pyfhel works with PyPtxt as  
    plaintext class and PyCtxt as cyphertext class.
    
    Example:
    >>> he = Pyfhel()
    >>> he.ContextGen(p=65537)
    >>> he.KeyGen(p=65537)
    >>> p1 = he.encode(4)
    >>> p2 = he.encode(2)
    >>> c1 = he.encrypt(p1)
    >>> c2 = he.encrypt(p2)
    >>> c1 = c1 + c2
    >>> p_res = he.decrypt(c1)
    6
    """
    def __cinit__(self):
        self.afseal = new Afseal()
    def __dealloc__(self):
        if self.afseal != NULL:
            del self.afseal
    def __iter__(self):
        return self
    
    # =========================================================================
    # ============================ CRYPTOGRAPHY ===============================
    # =========================================================================
    
    cpdef contextGen(self, long p, long m=2048, bool flagBatching=False,
                     long base=2, long sec=128, int intDigits=64,
                     int fracDigits = 32) except +:
        """Generates Homomorphic Encryption context based on parameters.
        
        Creates a HE context based in parameters, as well as integer,
        fractional and batch encoders. The HE context is required for any 
        other function (encryption/decryption,encoding/decoding, operations).
        
        Batch encoding is available if p is prime and p-1 is multiple of 2*m.
        
        Args:
            p (long): Plaintext modulus. All operations are modulo p.
            m (long=2048): Coefficient modulus. Higher allows more encrypted 
                      operations. In batch mode it is the number of integers
                      per ciphertext.
            flagBatching (bool=false): Set to true to enable batching.
            base (long=2): Polynomial base. Affects size of plaintexts and 
                      ciphertexts, and FRACTIONAL encoding. See encryptFrac.
            sec (long=128): Security level equivalent in AES.
                      Either 128 or 192.
            intDigits (int=64): when encrypting/encoding double, truncated
                      positions dedicated to integer part, out of 'm' positions
            fracDigits (int=32): when encrypting/encoding double, truncated
                      positions dedicated to fractional part, out of 'm'
                      
        Return:
            None
        """
        self.afseal.ContextGen(p, m, flagBatching, base,
                               sec,intDigits, fracDigits)
        
        
    cpdef void keyGen(self) except +:
        """Generates a pair of secret/Public Keys.
        
        Based on the current context, initializes one public and one secret key. 
        Args:
            None
                      
        Return:
            None
        """
        self.afseal.KeyGen()
    
    
    # .............................. ENCYRPTION ...............................
    cpdef PyCtxt encryptInt(self, int64_t value, PyCtxt ctxt=None) except +:
        """Encrypts a single int value into a PyCtxt ciphertext.
        
        Encrypts a single value using the current public key, based on the 
        current context. Value must either be an integer (int64_t)
        If provided a ciphertext, encrypts the value inside it. 
        
        Args:
            value (int): value to encrypt.
            ctxt (PyCtxt=None): Optional destination ciphertext.  
            
        Return:
            PyCtxt: the ciphertext containing the encrypted plaintext
        """
        if (ctxt._ptr_ctxt == NULL):
            ctxt = PyCtxt()
        self.afseal.encrypt(value, deref(ctxt._ptr_ctxt))
        ctxt._encoding = ENCODING_T.INTEGER
        return ctxt
    
    cpdef PyCtxt encryptFrac(self, double value, PyCtxt ctxt=None) except +:
        """Encrypts a single float value into a PyCtxt ciphertext.
        based on the 
        Encrypts a single value using the current secret key, based on the
        current context. Value must a decimal (float, double) that will get
        truncated both in the integer part (base^intDigits) and in the 
        decimal part (base^fracDigits).
        If provided a ciphertext, encrypts the plaintext inside it. 
        
        Args:
            value (float): value to encrypt.
            ctxt (PyCtxt=None): Optional destination ciphertext.  
            
        Return:
            PyCtxt: the ciphertext containing the encrypted plaintext
        """
        if (ctxt._ptr_ctxt == NULL):
            ctxt = PyCtxt()
        self.afseal.encrypt(value, deref(ctxt._ptr_ctxt))
        ctxt._encoding = ENCODING_T.FRACTIONAL
        return ctxt


    cpdef PyCtxt encryptBatch(self, vector[int64_t] vec,
                              PyCtxt ctxt=None) except +: 
        """Encrypts a 1D vector of integers into a PyCtxt ciphertext.
        
        Encrypts a 1D vector of integers using the current secret key,
        based on the current context. Plaintext must be a 1D numpy vector of integers.
        Requires batch mode. The vector needs to be in 'contiguous' or 'c' mode.
        If provided a ciphertext, encrypts the plaintext inside it. 
        
        Args:
            ptxt (np.ndarray[int, ndim=1, mode="c"]): plaintext to encrypt.
            ctxt (PyCtxt=None): Optional destination ciphertext.  
            
        Return:
            PyCtxt: the ciphertext containing the encrypted plaintext
        """
        if (ctxt._ptr_ctxt == NULL):
            ctxt = PyCtxt()
        self.afseal.encrypt(vec, deref(ctxt._ptr_ctxt)) 
        ctxt._encoding = ENCODING_T.BATCH
        return ctxt  
        
    cpdef PyCtxt encryptArray(self, int64_t[::1] arr,
                              PyCtxt ctxt=None) except +:
        """Encrypts a 1D numpy array of integers into a PyCtxt ciphertext.
        
        Encrypts a 1D numpy array of integers using the current secret key,
        based on the current context. Plaintext must be a 1D numpy vector of integers.
        Requires batch mode. The vector needs to be in 'contiguous' or 'c' mode.
        If provided a ciphertext, encrypts the plaintext inside it. 
        
        Args:
            ptxt (np.ndarray[int, ndim=1, mode="c"]): plaintext to encrypt.
            ctxt (PyCtxt=None): Optional destination ciphertext.  
            
        Return:
            PyCtxt: the ciphertext containing the encrypted plaintext
        """
        if (ctxt._ptr_ctxt == NULL):
            ctxt = PyCtxt()
        cdef vector[int64_t] vec;
        vec.assign(&arr[0], &arr[-1]+1)
        self.afseal.encrypt(vec, deref(ctxt._ptr_ctxt)) 
        ctxt._encoding = ENCODING_T.BATCH
        return ctxt  
    
    cpdef PyCtxt encryptPtxt(self, PyPtxt ptxt, PyCtxt ctxt=None) except +:
        """Encrypts an already encoded PyPtxt plaintext into a PyCtxt ciphertext.
        
        Encrypts an already encoded PyPtxt plaintext using the current secret key,
        based on the current context. Plaintext must be a PyPtxt.
        If provided a ciphertext, encrypts the plaintext inside it. 
        
        Args:
            ptxt (PyPtxt): plaintext to encrypt.
            ctxt (PyCtxt=None): Optional destination ciphertext.  
            
        Return:
            PyCtxt: the ciphertext containing the encrypted plaintext
            
        Raise:
            TypeError: if the plaintext doesn't have a valid type.
        """
        if (ptxt._ptr_ptxt == NULL):
            raise TypeError("<Pyfhel ERROR> PyPtxt Plaintext is empty")
        if (ctxt._ptr_ctxt == NULL):
            ctxt = PyCtxt()
        self.afseal.encrypt(deref(ptxt._ptr_ptxt), deref(ctxt._ptr_ctxt)) 
        ctxt._encoding = ptxt._encoding
        return ctxt

    def encrypt(self, ptxt not None, PyCtxt ctxt=None):
        """Encrypts any valid plaintext into a PyCtxt ciphertext.
        
        Encrypts a plaintext using the current secret key, based on the current context.
        Plaintext must be an integer (int), a decimal that will get truncated (double),
        a PyPtxt encoded plaintext, or in Batch mode a 1D numpy vector of integers.
        Selects the encryption function based on type.
        
        If provided a ciphertext, encrypts the plaintext inside it. 
        
        Args:
            ptxt (PyPtxt|int|double|np_1d_int_array): plaintext to encrypt.
            ctxt (PyCtxt=None): Optional destination ciphertext.  
            
        Return:
            PyCtxt: the ciphertext containing the encrypted plaintext
            
        Raise:
            TypeError: if the plaintext doesn't have a valid type.
        """            
        if isinstance(ptxt, PyPtxt):
            return self.encryptPtxt(ptxt, ctxt)
        elif isinstance(ptxt, np.ndarray):
            if (ptxt.ndim is not 1) or (ptxt.dtype is not int):
                raise TypeError('<Pyfhel ERROR> Plaintext numpy array is not'
                                '1D vector of int values, cannot encrypt.')
            return self.encryptBatch(ptxt, ctxt)  
        elif isinstance(ptxt, float):
            return self.encryptFrac(<float>ptxt, ctxt)   
        elif isinstance(ptxt, Number):
            return self.encryptInt(<int>ptxt, ctxt)  
        else:
            raise TypeError('<Pyfhel ERROR> Plaintext type \['+type(ptxt)+
                            '\] not supported for encryption')
    
    # .............................. DECRYPTION ...............................
    cpdef int64_t decryptInt(self, PyCtxt ctxt) except +:
        """Decrypts a PyCtxt ciphertext into a single int value.
        
        Decrypts a PyCtxt ciphertext using the current secret key, based on
        the current context. PyCtxt encoding must be INTEGER.
        
        Args:
            ctxt (PyCtxt=None): ciphertext to decrypt. 
            
        Return:
            int: the decrypted integer value
            
        Raise:
            RuntimeError: if the ciphertext encoding isn't ENCODING_T.INTEGER.
        """
        if (ctxt._encoding != ENCODING_T.INTEGER):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyCtxt")
        cdef int64_t output_value = 0
        self.afseal.decrypt(deref(ctxt._ptr_ctxt), output_value)
        return output_value
    
    cpdef double decryptFrac(self, PyCtxt ctxt) except +:
        """Decrypts a PyCtxt ciphertext into a single float value.
        
        Decrypts a PyCtxt ciphertext using the current secret key, based on
        the current context. PyCtxt encoding must be FRACTIONAL.
        
        Args:
            ctxt (PyCtxt): ciphertext to decrypt. 
            
        Return:
            float: the decrypted float value
            
        Raise:
            RuntimeError: if the ciphertext encoding isn't ENCODING_T.FRACTIONAL.
        """
        if (ctxt._encoding != ENCODING_T.FRACTIONAL):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyCtxt")
        cdef double output_value = 0
        self.afseal.decrypt(deref(ctxt._ptr_ctxt), output_value)
        return output_value
    
    cpdef vector[int64_t] decryptBatch(self, PyCtxt ctxt) except +:
                
        """Decrypts a PyCtxt ciphertext into a 1D numpy vector of integers.
        
        Decrypts a PyCtxt ciphertext  using the current secret key, based on
        the current context. If provided an output vector, decrypts the
        ciphertext inside it. 
        
        Args:
            ctxt (PyCtxt): ciphertext to decrypt. 
            
        Return:
            PyCtxt: the ciphertext containing the encrypted plaintext
            
        Raise:
            RuntimeError: if the ciphertext encoding isn't ENCODING_T.BATCH.
        """
        if (ctxt._encoding != ENCODING_T.BATCH):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyCtxt")
        return self.afseal.decrypt(deref(ctxt._ptr_ctxt))
        
    cpdef int64_t[::1] decryptArray(self, PyCtxt ctxt) except +:
                
        """Decrypts a PyCtxt ciphertext into a 1D numpy vector of integers.
        
        Decrypts a PyCtxt ciphertext  using the current secret key, based on
        the current context. If provided an output vector, decrypts the
        ciphertext inside it. 
        
        Args:
            ctxt (PyCtxt): ciphertext to decrypt. 
            
        Return:
            PyCtxt: the ciphertext containing the encrypted plaintext
            
        Raise:
            RuntimeError: if the ciphertext encoding isn't ENCODING_T.BATCH.
        """
        if (ctxt._encoding != ENCODING_T.BATCH):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyCtxt")
        cdef vector[int64_t] output_vector=self.afseal.decrypt(deref(ctxt._ptr_ctxt))  
        cdef int64_t[::1] output_array = <int64_t [:output_vector.size()]>output_vector.data()
        return output_array
    
    cpdef PyPtxt decryptPtxt(self, PyCtxt ctxt, PyPtxt ptxt=None) except +:
        """Decrypts a PyCtxt ciphertext into a PyPtxt plaintext.
        
        Decrypts a PyCtxt ciphertext using the current secret key, based on
        the current context. No regard to encoding (decode PyPtxt to obtain 
        value).
        
        Args:
            ctxt (PyCtxt): ciphertext to decrypt. 
            ptxt (PyPtxt=None): Optional destination plaintext.
            
        Return:
            PyPtxt: the decrypted plaintext
        """
        if (ptxt._ptr_ptxt == NULL):
            ptxt = PyPtxt()
        self.afseal.decrypt(deref(ctxt._ptr_ctxt), deref(ptxt._ptr_ptxt))
        ptxt._encoding = ctxt._encoding
        return ptxt
    
    def decrypt(self, PyCtxt ctxt, bool decode_value=False, PyPtxt ptxt=None):
        """Decrypts any valid PyCtxt into either a PyPtxt ciphertext or a value.
        
        Decrypts a PyCtxt ciphertext using the current secret key, based on the
        current context. Outputs an integer (int), a truncated decimal (float),
        a PyPtxt encoded plaintext, or in Batch mode a 1D numpy vector of integers.
        Selects the encryption function based on type.
        
        If provided a plaintext, decrypts the ciphertext inside it. 
        
        Args:
            ctxt (PyCtxt|int|double|np_1d_int_array): plaintext to encrypt.
            decrypt_value (bool=False): decrypt and decode (return value),
                                        or only decrypt (return ptxt).
            ptxt (PyPtxt=None): Optional destination ciphertext.  
            
        Return:
            PyCtxt|int|double|vector[int]: the decrypted result
            
        Raise:
            TypeError: if the plaintext doesn't have a valid type.
        """
        if (decode_value):
            if (ctxt._encoding == ENCODING_T.BATCH):
                return self.decryptBatch(ctxt)
            elif (ctxt._encoding == ENCODING_T.FRACTIONAL):
                return self.decryptFrac(ctxt)
            elif (ctxt._encoding == ENCODING_T.INTEGER):
                return self.decryptInt(ctxt)
            elif (ctxt._encoding == ENCODING_T.UNDEFINED):
                raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyCtxt")
        else: # Decrypt to plaintext        
            if (ptxt._ptr_ptxt == NULL):
                ptxt = PyPtxt()
            return self.decryptPtxt(ctxt, ptxt)
        
        
    # ................................ OTHER ..................................
    cpdef int noiseLevel(self, PyCtxt ctxt) except +:
        """Computes the invariant noise budget (in bits) of a PyCtxt ciphertext.
        
        The invariant noise budget measures the amount of room there is for the
        noise to grow while ensuring correct decryptions.
        Decrypts a PyCtxt ciphertext using the current secret key, based on the
        current context.
        
        Args:
            ctxt (PyCtxt): ciphertext to be measured.
            
        Return:
            int: the noise budget level
        """
        return self.afseal.noiseLevel(deref(ctxt._ptr_ctxt))
    
    cpdef void rotateKeyGen(self, int bitCount) except +:
        """Generates a rotation Key.
        
        Generates a rotation Key, used in BATCH mode to rotate cyclically the
        values inside the encrypted vector.
        
        Based on the current context, initializes one rotation key. 
        
        Args:
            bitCount (int): Bigger means faster but noisier (will require
                            relinearization). Needs to be within [1, 60]
                      
        Return:
            None
        """
        self.afseal.rotateKeyGen(bitCount)
        
    cpdef void relinKeyGen(self, int bitCount, int size) except +:
        """Generates a relinearization Key.
        
        Generates a relinearization Key, used to reduce size of the ciphertexts
        when multiplying or exponentiating them. This is needed due to the fact
        that ciphertexts grow in size after encrypted mults/exponentiations.
        
        Based on the current context, initializes one relinearization key. 
        
        Args:
            bitCount (int): Bigger means faster but noisier (will require
                            relinearization). Needs to be within [1, 60]
                      
        Return:
            None
        """
        self.afseal.rotateKeyGen(bitCount)        
        
    cpdef void relinearize(self, PyCtxt ctxt) except +:
        """Relinearizes a ciphertext.
        
        Relinearizes a ciphertext. This functions relinearizes ctxt, reducing
        its size down to 2. If the size of encrypted is K+1, the given evaluation
        keys need to have size at least K-1. 
        
        To relinearize a ciphertext of size M >= 2 back to size 2, we actually need
        M-2 evaluation keys. Attempting to relinearize a too large ciphertext with
        too few evaluation keys will result in an exception being thrown.
                
        Args:
            bitCount (int): The bigger the faster but noisier (will require
                            relinearization). Needs to be within [1, 60]
                      
        Return:
            None
        """
        self.afseal.relinearize(deref(ctxt._ptr_ctxt))  
    
    # =========================================================================
    # ============================== ENCODING =================================
    # =========================================================================
    # ............................... ENCODE ..................................
    cpdef PyPtxt encodeInt(self, int64_t &value, PyPtxt ptxt=None) except +:
        """Encodes a single int value into a PyPtxt plaintext.
        
        Encodes a single intvalue based on the current context.
        If provided a plaintext, encodes the value inside it. 
        
        Args:
            value (int): value to encrypt.
            ptxt (PyPtxt=None): Optional destination plaintext.  
            
        Return:
            PyPtxt: the plaintext containing the encoded value
        """
        if (ptxt._ptr_ptxt == NULL):
            ptxt = PyPtxt()
        self.afseal.encode(value, deref(ptxt._ptr_ptxt))
        ptxt._encoding = ENCODING_T.INTEGER
        return ptxt
    
    cpdef PyPtxt encodeFrac(self, double &value, PyPtxt ptxt=None) except +:
        """Encodes a single float value into a PyPtxt plaintext.
        
        Encodes a single float value based on the current context.
        If provided a plaintext, encodes the value inside it. 
        
        Args:
            value (float): value to encrypt.
            ptxt (PyPtxt=None): Optional destination plaintext.   
            
        Return:
            PyPtxt: the plaintext containing the encoded value
        """
        if (ptxt._ptr_ptxt == NULL):
            ptxt = PyPtxt()
        self.afseal.encode(value, deref(ptxt._ptr_ptxt))
        ptxt._encoding = ENCODING_T.FRACTIONAL
        return ptxt
    
    cpdef PyPtxt encodeBatch(self, vector[int64_t]& vec, PyPtxt ptxt=None) except +: 
        """Encodes a 1D list of integers into a PyPtxt plaintext.
        
        Encodes a 1D vector of integers based on the current context.
        Plaintext must be a 1D vector of integers. Requires batch mode.
        In Numpy the vector needs to be in 'contiguous' or 'c' mode.
        If provided a plaintext, encodes the vector inside it. 
        Maximum size of the vector defined by parameter 'm' from context.
        
        Args:
            vec (vector[int64_t]): vector to encode.
            ptxt (PyPtxt=None): Optional destination plaintext.  
            
        Return:
            PyPtxt: the plaintext containing the encoded vector.
        """
        if (ptxt._ptr_ptxt == NULL):
            ptxt = PyPtxt()
        self.afseal.encode(vec, deref(ptxt._ptr_ptxt))
        ptxt._encoding = ENCODING_T.BATCH
        return ptxt  
    
    cpdef PyPtxt encodeArray(self, int64_t[::1] &arr, PyPtxt ptxt=None) except +:
        """Encodes a 1D numpy array of integers into a PyPtxt plaintext.
        
        Encodes a 1D numpy vector of integers based on the current context.
        Plaintext must be a 1D vector of integers. Requires batch mode.
        In Numpy the vector needs to be in 'contiguous' or 'c' mode.
        If provided a plaintext, encodes the vector inside it. 
        Maximum size of the vector defined by parameter 'm' from context.
        
        Args:
            vec (vector[int64_t]): vector to encode.
            ptxt (PyPtxt=None): Optional destination plaintext.  
            
        Return:
            PyPtxt: the plaintext containing the encoded vector.
        """
        if (ptxt._ptr_ptxt == NULL):
            ptxt = PyPtxt()
        cdef vector[int64_t] vec=[0];
        vec.assign(&arr[0], &arr[-1]+1)
        self.afseal.encode(vec, deref(ptxt._ptr_ptxt)) 
        ptxt._encoding = ENCODING_T.BATCH
        return ptxt  
    
    def encode(self, val_vec not None, PyPtxt ptxt=None):
        """Encodes any valid value/vector into a PyPtxt plaintext.
        
        Encodes any valid value/vector based on the current context.
        Value/Vector must be an integer (int), a decimal that will get 
        truncated (float), or in Batch mode a 1D vector of integers.
        
        If provided a plaintext, encodes the vector inside it. 
        
        Args:
            val_vec (int|float|vector[int64_t]): value/vector to encode.
            ptxt (PyPtxt=None): Optional destination plaintext. 
            
        Return:
            PyPtxt: the plaintext containing the encoded vector.
            
        Raise:
            TypeError: if the val_vec doesn't have a valid type.
        """            
        if isinstance(val_vec, np.ndarray):
            if (val_vec.ndim is not 1) or (val_vec.dtype is not int):
                raise TypeError('<Pyfhel ERROR> Plaintext numpy array is not'
                                '1D vector of int values, cannot encode.')
            return self.encodeBatch(val_vec, ptxt)  
        elif isinstance(val_vec, FLOAT_T):
            return self.encodeValue(<float>val_vec, ptxt)   
        elif isinstance(val_vec, Number):
            return self.encodeValue(<int>val_vec, ptxt)  
        else:
            raise TypeError('<Pyfhel ERROR> Value/Vector type \['+type(val_vec)+
                            '\] not supported for encoding')      

    # ................................ DECODE .................................
    cpdef int64_t decodeInt(self, PyPtxt ptxt) except +:
        """Decodes a PyPtxt plaintext into a single int value.
        
        Decodes a PyPtxt plaintext into a single int value based on
        the current context. PyPtxt encoding must be INTEGER.
        
        Args:
            ptxt (PyPtxt=None): plaintext to decode. 
            
        Return:
            int64_t: the decoded integer value
            
        Raise:
            RuntimeError: if the ciphertext encoding isn't ENCODING_T.INTEGER.
        """
        if (ptxt._encoding != ENCODING_T.INTEGER):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyPtxt")
        cdef int64_t output_value=0
        self.afseal.decode(deref(ptxt._ptr_ptxt), output_value)
        return output_value
    
    cpdef double decodeFrac(self, PyPtxt ptxt) except +:
        """Decodes a PyPtxt plaintext into a single float value.
        
        Decodes a PyPtxt plaintext into a single float value based on
        the current context. PyPtxt encoding must be FRACTIONAL.
        
        Args:
            ptxt (PyPtxt): plaintext to decode.
            
        Return:
            double: the decoded float value
            
        Raise:
            RuntimeError: if the ciphertext encoding isn't ENCODING_T.FRACTIONAL.
        """
        if (ptxt._encoding != ENCODING_T.FRACTIONAL):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyPtxt")
        cdef double output_value=0
        self.afseal.decode(deref(ptxt._ptr_ptxt), output_value)
        return output_value
    
    cpdef vector[int64_t] decodeBatch(self, PyPtxt ptxt) except +:
        """Decodes a PyPtxt plaintext into a 1D vector of integers.
        
        Decodes a PyPtxt plaintext into a 1D vector of integers based on
        the current context. PyPtxt encoding must be BATCH.
        
        Args:
            ptxt (PyPtxt): plaintext to decode.
            
        Return:
            vector[int64_t]: the vectort containing the decoded values
            
        Raise:
            RuntimeError: if the plaintext encoding isn't ENCODING_T.BATCH.
        """
        if (ptxt._encoding != ENCODING_T.BATCH):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyPtxt")
        cdef vector[int64_t] output_vector=self.afseal.decode(deref(ptxt._ptr_ptxt))
        return output_vector
    
    cpdef int64_t[::1] decodeArray(self, PyPtxt ptxt) except +:
                
        """Decodes a PyPtxt plaintext into a 1D numpy numpy  of integers.
        
        Decodes a PyPtxt plaintext into a 1D numpy array of integers based on
        the current context. PyPtxt encoding must be BATCH.
        
        Args:
            ptxt (PyPtxt): plaintext to decode.
            
        Return:
            vector[int64_t]: the vectort containing the decoded values
            
        Raise:
            RuntimeError: if the plaintext encoding isn't ENCODING_T.BATCH.
        """
        if (ptxt._encoding != ENCODING_T.BATCH):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyPtxt")
        cdef vector[int64_t] output_vector = self.afseal.decode(deref(ptxt._ptr_ptxt))
        cdef int64_t[::1] output_array = <int64_t [:output_vector.size()]>output_vector.data()
        return output_array
        
    def decode(self, PyPtxt ptxt):
        """Decodes any valid PyPtxt into a value or vector.
        
        Decodes a PyPtxt plaintext based on the current context.
        Outputs an integer (int), a truncated decimal (float), or in 
        Batch mode a 1D vector of integers. Automatically selects the
        decoding function based on type.
    
        Args:
            ptxt (PyPtxt|int|double|np_1d_int_array): plaintext to encrypt.
            ctxt (PyCtxt=None): Optional destination ciphertext.  
            
        Return:
            int|double|vector[int]: the decoded value or vector;
            
        Raise:
            TypeError: if the plaintext doesn't have a valid type.
        """
        if (ptxt._encoding == ENCODING_T.BATCH):
            return self.decodeBatch(ptxt)
        elif (ptxt._encoding == ENCODING_T.FRACTIONAL):
            return self.decodeFrac(ptxt)
        elif (ptxt._encoding == ENCODING_T.INTEGER):
            return self.decodeInt(ptxt)
        elif (ptxt._encoding == ENCODING_T.UNDEFINED):
            raise RuntimeError("<Pyfhel ERROR> wrong encoding type in PyCtxt")

            
    # =========================================================================
    # ============================= OPERATIONS ================================
    # =========================================================================
    cpdef PyCtxt square(self, PyCtxt ctxt, bool in_new_ctxt=False) except +:
        """Square PyCtxt ciphertext value/s.
    
        Args:
            ctxt (PyCtxt): ciphertext whose values are squared.  
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.square(deref(new_ctxt._ptr_ctxt))
            return new_ctxt
        else:
            self.afseal.square(deref(ctxt._ptr_ctxt))
            return ctxt
        
    cpdef PyCtxt negate(self, PyCtxt ctxt, bool in_new_ctxt=False) except +:
        """Negate PyCtxt ciphertext value/s.
    
        Args:
            ctxt (PyCtxt): ciphertext whose values are negated.   
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.negate(deref(new_ctxt._ptr_ctxt))
            return new_ctxt
        else:
            self.afseal.negate(deref(ctxt._ptr_ctxt))
            return ctxt

        
    cpdef PyCtxt add(self, PyCtxt ctxt, PyCtxt ctxt_other, bool in_new_ctxt=False) except +:
        """Sum two PyCtxt ciphertexts.
        
        Sums two ciphertexts. Encoding must be the same. Requires same
        context and encryption with same public key. The result is applied
        to the first ciphertext.
    
        Args:
            ctxt (PyCtxt): ciphertext whose values are added with ctxt_other.  
            ctxt_other (PyCtxt): ciphertext left untouched.  
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (ctxt._encoding != ctxt_other._encoding):
            raise RuntimeError("<Pyfhel ERROR> encoding type mistmatch in add terms")
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.add(deref(new_ctxt._ptr_ctxt), deref(ctxt_other._ptr_ctxt))
            return new_ctxt
        else:
            self.afseal.add(deref(ctxt._ptr_ctxt), deref(ctxt_other._ptr_ctxt))
            return ctxt
        
        
    cpdef PyCtxt add_plain (self, PyCtxt ctxt, PyPtxt ptxt, bool in_new_ctxt=False) except +:
        """Sum a PyCtxt ciphertext and a PyPtxt plaintext.
        
        Sums a ciphertext and a plaintext. Encoding must be the same. Requires
        same context and encryption with same public key. The result is applied
        to the first ciphertext.
    
        Args:
            ctxt (PyCtxt): ciphertext whose values are added with ptxt.  
            ptxt (PyPtxt): plaintext left untouched.  
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (ctxt._encoding != ptxt._encoding):
            raise RuntimeError("<Pyfhel ERROR> encoding type mistmatch in add terms")
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.add(deref(new_ctxt._ptr_ctxt), deref(ptxt._ptr_ptxt))
            return new_ctxt
        else:
            self.afseal.add(deref(ctxt._ptr_ctxt), deref(ptxt._ptr_ptxt))
            return ctxt

            
    cpdef PyCtxt sub (self, PyCtxt ctxt, PyCtxt ctxt_other, bool in_new_ctxt=False) except +:
        """Substracts one PyCtxt ciphertext from another.
        
        Substracts one ciphertext from another. Encoding must be the same.
        Requires same context and encryption with same public key. The result
        is stored/applied to the first ciphertext.
    
        Args:
            ctxt (PyCtxt): ciphertext whose values get substracted by ctxt_other.  
            ctxt_other (PyCtxt): ciphertext left untouched, whose values are
                                substracted from ctxt.
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (ctxt._encoding != ctxt_other._encoding):
            raise RuntimeError("<Pyfhel ERROR> encoding type mistmatch in sub terms")
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.sub(deref(new_ctxt._ptr_ctxt), deref(ctxt_other._ptr_ctxt))
            return new_ctxt
        else:
            self.afseal.sub(deref(ctxt._ptr_ctxt), deref(ctxt_other._ptr_ctxt))
            return ctxt
        
    cpdef PyCtxt sub_plain (self, PyCtxt ctxt, PyPtxt ptxt, bool in_new_ctxt=False) except +:
        """Substracts a PyCtxt ciphertext and a plaintext.
        
        Performs ctxt = ctxt - ptxt. Encoding must be the same. Requires same
        context and encryption with same public key. The result is stored/applied
        to the ciphertext.
    
        Args:
            ctxt (PyCtxt): ciphertext whose values get substracted by ctxt_other.  
            ptxt (PyPtxt): plaintext left untouched, whose values are
                                substracted from ctxt.
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (ctxt._encoding != ptxt._encoding):
            raise RuntimeError("<Pyfhel ERROR> encoding type mistmatch in sub terms")
        
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.sub(deref(new_ctxt._ptr_ctxt), deref(ptxt._ptr_ptxt))
            return new_ctxt
        else:
            self.afseal.sub(deref(ctxt._ptr_ctxt), deref(ptxt._ptr_ptxt))
            return ctxt

        
    cpdef PyCtxt multiply (self, PyCtxt ctxt, PyCtxt ctxt_other, bool in_new_ctxt=False) except +:
        """Multiply first PyCtxt ciphertext by the second PyCtxt ciphertext.
        
        Multiplies two ciphertexts. Encoding must be the same. Requires same
        context and encryption with same public key. The result is applied
        to the first ciphertext.
    
        Args:
            ctxt (PyCtxt): ciphertext whose values are multiplied with ctxt_other.  
            ctxt_other (PyCtxt): ciphertext left untouched.  
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (ctxt._encoding != ctxt_other._encoding):
            raise RuntimeError("<Pyfhel ERROR> encoding type mistmatch in mult terms")
        
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.multiply(deref(new_ctxt._ptr_ctxt), deref(ctxt_other._ptr_ctxt))
            return new_ctxt
        else:
            self.afseal.multiply(deref(ctxt._ptr_ctxt), deref(ctxt_other._ptr_ctxt))
            return ctxt
        
    cpdef PyCtxt multiply_plain (self, PyCtxt ctxt, PyPtxt ptxt, bool in_new_ctxt=False) except +:
        """Multiply a PyCtxt ciphertext and a PyPtxt plaintext.
        
        Multiplies a ciphertext and a plaintext. Encoding must be the same. Requires
        same context and encryption with same public key. The result is applied
        to the first ciphertext.
    
        Args:
            ctxt (PyCtxt): ciphertext whose values are multiplied with ptxt.  
            ptxt (PyPtxt): plaintext left untouched.  
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (ctxt._encoding != ptxt._encoding):
            raise RuntimeError("<Pyfhel ERROR> encoding type mistmatch in mult terms")   
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.multiply(deref(new_ctxt._ptr_ctxt), deref(ptxt._ptr_ptxt))     
            return new_ctxt
        else:
            self.afseal.multiply(deref(ctxt._ptr_ctxt), deref(ptxt._ptr_ptxt))     
            return ctxt
        
    cpdef PyCtxt rotate(self, PyCtxt ctxt, int k, bool in_new_ctxt=False) except +:
        """Rotates cyclically PyCtxt ciphertext values k positions.
        
        Performs a cyclic rotation over a cyphertext encoded in BATCH mode. 
        Requires previously initialized rotation keys with rotateKeyGen().
    
        Args:
            ctxt (PyCtxt): ciphertext whose values are rotated.
            k (int): number of positions to rotate.
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (ctxt._encoding != ENCODING_T.BATCH):
            raise RuntimeError("<Pyfhel ERROR> BATCH encoding required for rotation")
        
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.rotate(deref(new_ctxt._ptr_ctxt), k)   
            return new_ctxt
        else:
            self.afseal.rotate(deref(ctxt._ptr_ctxt), k)   
            return ctxt
        
    cpdef PyCtxt power(self, PyCtxt ctxt, uint64_t expon, bool in_new_ctxt=False) except +:
        """Exponentiates PyCtxt ciphertext value/s to expon power.
        
        Performs an exponentiation over a cyphertext. Requires previously
        initialized relinearization keys with relinearizeKeyGen(), since
        it applies relinearization after each multiplication.
    
        Args:
            ctxt (PyCtxt): ciphertext whose value/s are exponetiated.  
            expon (uint64_t): exponent.
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.exponentiate(deref(new_ctxt._ptr_ctxt), expon)  
            return new_ctxt
        else:
            self.afseal.exponentiate(deref(ctxt._ptr_ctxt), expon) 
            return ctxt
        
    cpdef PyCtxt polyEval(self, PyCtxt ctxt,
                        vector[int64_t] coeffPoly, bool in_new_ctxt=False) except +:
        """Evaluates polynomial in PyCtxt ciphertext value/s.
        
        Evaluates a polynomial given by integer coefficients. Requires 
        previously initialized relinearization keys with relinearizeKeyGen(),
        since it applies relinearization after each multiplication.
    
        Args:
            ctxt (PyCtxt): ciphertext whose value/s are exponetiated.  
            coeffPoly (vector[int64_t]): Polynomial coefficients:
                        coeffPoly[0]*ctxt^2 + coeffPoly[1]*ctxt + coeffPoly[2]   
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """
        
        if (ctxt._encoding != ENCODING_T.BATCH) and (ctxt._encoding != ENCODING_T.INTEGER) :
            raise RuntimeError("<Pyfhel ERROR> encoding type must be INTEGER or BATCH")
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.polyEval(deref(new_ctxt._ptr_ctxt), coeffPoly)      
            return new_ctxt
        else:
            self.afseal.polyEval(deref(ctxt._ptr_ctxt), coeffPoly)    
            return ctxt
        
    cpdef PyCtxt polyEval_double (self, PyCtxt ctxt,
                 vector[double] coeffPoly, bool in_new_ctxt=False) except +:
        """Evaluates polynomial in PyCtxt ciphertext value/s.
        
        Evaluates a polynomial given by float coefficients. Requires 
        previously initialized relinearization keys with relinearizeKeyGen(),
        since it applies relinearization after each multiplication.
    
        Args:
            ctxt (PyCtxt): ciphertext whose value/s are exponetiated.  
            coeffPoly (vector[float]): Polynomial coefficients:
                        coeffPoly[0]*ctxt^2 + coeffPoly[1]*ctxt + coeffPoly[2]   
            in_new_ctxt (bool=False): apply operation to a newly
                        created ciphertext instead of input cyphertext
            
        Return:
            PyCtxt resulting ciphertext, either the input transformed or a new one
        """        
        if (ctxt._encoding != ENCODING_T.BATCH) or (ctxt._encoding != ENCODING_T.INTEGER) :
            raise RuntimeError("<Pyfhel ERROR> encoding type must be INTEGER or BATCH")
        if (in_new_ctxt):
            new_ctxt = PyCtxt(ctxt)
            self.afseal.polyEval(deref(new_ctxt._ptr_ctxt), coeffPoly)      
            return new_ctxt
        else:
            self.afseal.polyEval(deref(ctxt._ptr_ctxt), coeffPoly)    
            return ctxt
        
        
        
    
    # =========================================================================
    # ================================ I/O ====================================
    # =========================================================================    
    cpdef bool saveContext(self, string fileName) except +:
        """Saves current context in a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.saveContext(fileName)
    
    cpdef bool restoreContext(self, string fileName) except +:
        """Restores current context from a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.restoreContext(fileName)

    cpdef bool savepublicKey(self, string fileName) except +:
        """Saves current public key in a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.saveContext(fileName)
    
    cpdef bool restorepublicKey(self, string fileName) except +:
        """Restores current public key from a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.restoreContext(fileName)

    cpdef bool savesecretKey(self, string fileName) except +:
        """Saves current secret key in a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.saveContext(fileName)
    
    cpdef bool restoresecretKey(self, string fileName) except +:
        """Restores current secret key from a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.restoreContext(fileName)
    
    cpdef bool saverelinKey(self, string fileName) except +:
        """Saves current relinearization keys in a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.saverelinKey(fileName)
    
    cpdef bool restorerelinKey(self, string fileName) except +:
        """Restores current relinearization keys from a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.restorerelinKey(fileName)
    
    cpdef bool saverotateKey(self, string fileName) except +:
        """Saves current rotation Keys from a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.saverotateKey(fileName)
    
    cpdef bool restorerotateKey(self, string fileName) except +:
        """Restores current rotation Keys from a file
        
        Args:
            fileName (string): Name of the file.   
            
        Return:
            bool: Result, True if OK, False otherwise.
        """
        return self.afseal.restorerotateKey(fileName)
    
    
    
    # =========================================================================
    # ============================== AUXILIARY ================================
    # =========================================================================
    cpdef bool batchEnabled(self) except +:
        """Flag of batch enabled. 
            
        Return:
            bool: Result, True if enabled, False if disabled.
        """
        return self.afseal.batchEnabled()
    
    cpdef long relinBitCount(self) except +:
        """Relinearization bit count for current evaluation keys.
            
        Return:
            long: [1-60], based on relinKeyGen parameter.
        """
        return self.afseal.relinBitCount()
    
    # GETTERS
    cpdef int getnSlots(self) except +:
        """Maximum umber of slots fitting in a ciphertext in BATCH encoding mode.
            
        Return:
            int: Maximum umber of slots.
        """
        return self.afseal.getnSlots()
    
    cpdef int getp(self) except +:
        """Plaintext modulus of the current context. All operations are modulo p.
            
        Return:
            int: Plaintext modulus.
        """
        return self.afseal.getp()
    
    cpdef int getm(self) except +:
        """Plaintext coefficient of the current context.
        
        The more, the bigger the ciphertexts are, thus allowing for more operations
        with correct decryption. Also, number of values in a ciphertext in BATCH 
        encoding mode. 
        
            
        Return:
            int: Plaintext coefficient.
        """
        return self.afseal.getm()
    
    cpdef int getbase(self) except +:
        """Polynomial base.
        
        Polynomial base of polynomials that conform cyphertexts and plaintexts. 
        Affects size of plaintexts and ciphertexts, and FRACTIONAL encoding.
        See encryptFrac. 
        
        Return:
            int: Polynomial base.
        """
        return self.afseal.getbase()
    
    cpdef int getsec(self) except +:
        """Security level equivalent in AES.
        
        Return:
            int: Security level equivalent in AES. Either 128 or 192.
        """
        return self.afseal.getsec()
    
    cpdef int getintDigits(self) except +:
        """Integer digits in FRACTIONAL encoding.
        
        When encrypting/encoding double (FRACTIONAL encoding), truncated
        positions dedicated to integer part, out of 'm' positions.
        
        Return:
            int: number of integer digits.
        """
        return self.afseal.getintDigits()
    
    cpdef int getfracDigits(self) except +:
        """Decimal digits in FRACTIONAL encoding.
        
        When encrypting/encoding double (FRACTIONAL encoding), truncated
        positions dedicated to deimal part, out of 'm' positions.
        
        Return:
            int: number of fractional digits.
        """
        return self.afseal.getfracDigits()
    
    cpdef bool getflagBatch(self) except +:
        """Flag for BATCH encoding mode.
        
        If True, allows operations over vectors encrypted in single PyCtxt 
        ciphertexts. Defined in context creation based on the chosen values
        of p and m, and activated in context creation with a flag.
        
        Return:
            bool: flag for enabled BATCH encoding and operating.
        """
        return self.afseal.getflagBatch()